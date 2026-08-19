import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart'
    hide NotificationVisibility;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/ble/ble_permissions.dart';
import '../core/ble/mesh_gatt.dart';
import '../core/ble/sos_advertisement.dart';
import '../core/data/database.dart';
import '../core/model/model.dart';
import '../feature/gateway/gateway_bridge.dart';
import '../feature/join/join_screen.dart';
import '../feature/location/location_capture.dart';
import '../feature/onboarding/onboarding_screen.dart';
import '../feature/rooms/room_message_packet.dart';
import '../feature/rooms/rooms_screen.dart';
import '../feature/sos/sos_payload.dart';
import '../feature/sos/sos_repository.dart';
import '../feature/sos/sos_screen.dart';
import '../feature/voice/voice_recorder.dart';
import 'mesh_bridge.dart';
import 'mesh_bridge_client.dart';
import 'mesh_event_controller.dart';
import 'providers.dart';

const int _notificationServiceId = 1001;
const String _notificationChannelId = 'meshsetu-event-v2';
const String _sosNotificationChannelId = 'meshsetu-sos-alerts-v1';
final FlutterLocalNotificationsPlugin _sosNotifications =
    FlutterLocalNotificationsPlugin();
bool _sosNotificationsInitialized = false;

Future<void> _showSosNotification({
  required ReceivedObject received,
  required String detail,
}) async {
  try {
    if (!_sosNotificationsInitialized) {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _sosNotifications.initialize(settings: settings);
      _sosNotificationsInitialized = true;
    }
    var notificationId = received.envelope.objectId & 0x7fffffff;
    if (notificationId == 0) notificationId = 1;
    await _sosNotifications.show(
      id: notificationId,
      title: 'SOS RECEIVED',
      body: detail,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _sosNotificationChannelId,
          'SOS alerts',
          channelDescription: 'Nearby MeshSetu emergency signals',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          ticker: 'SOS received',
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
          onlyAlertOnce: false,
        ),
      ),
    );
  } catch (_) {
    // A notification failure must not stop BLE relaying.
  }
}

Future<void> _showCompactSosNotification(MeshSosAdvertisement alert) async {
  try {
    if (!_sosNotificationsInitialized) {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _sosNotifications.initialize(settings: settings);
      _sosNotificationsInitialized = true;
    }
    final id = Object.hash(alert.originId, alert.sequence) & 0x7fffffff;
    await _sosNotifications.show(
      id: id == 0 ? 1 : id,
      title: alert.isTest ? 'TEST SOS RECEIVED' : 'SOS RECEIVED',
      body: alert.isTest
          ? 'Nearby BLE transport test received.'
          : 'Nearby emergency alert received. Details may follow.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _sosNotificationChannelId,
          'SOS alerts',
          channelDescription: 'Nearby MeshSetu emergency signals',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
        ),
      ),
    );
  } catch (_) {
    // BLE relaying must remain live if Android rejects an alert.
  }
}

/// Port of `in.meshsetu.app.MeshEventService`'s foreground service. The mesh
/// controller is deliberately created in this task isolate, not the UI one.
@pragma('vm:entry-point')
void meshEventTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_MeshEventTaskHandler());
}

class _MeshEventTaskHandler extends TaskHandler {
  MeshEventController? _controller;
  bool _sosPending = false;
  bool _debugLossEnabled = false;
  StreamSubscription<ReceivedObject>? _incomingSubscription;
  int _notificationGeneration = 0;
  final Set<String> _compactAlertKeys = {};

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    DartPluginRegistrant.ensureInitialized();
    try {
      final controller = MeshEventController(
        zoneResolver: MeshEventController.demoZoneResolver,
        onPeerState: (peers) => FlutterForegroundTask.sendDataToMain({
          'status': 'mesh_peers',
          'peers': [
            for (final peer in peers)
              {
                'peerId': peer.peerId,
                'connected': peer.connected,
                'mtu': peer.mtu,
                'rssi': peer.rssi,
                'queuedObjects': peer.queuedObjects,
                'lastSeenMs': peer.lastSeenMs,
              },
          ],
        }),
        onMeshStatus: (status) => FlutterForegroundTask.sendDataToMain({
          'status': 'mesh_status',
          'value': status,
        }),
        onMetrics: (metrics) => FlutterForegroundTask.sendDataToMain({
          'status': 'mesh_metric',
          'metrics': [
            for (final metric in metrics)
              {
                'kind': metric.kind,
                'peerId': metric.peerId,
                'value': metric.value,
                'objectId': metric.objectId,
                'detail': metric.detail,
              },
          ],
        }),
        onBeaconObservations: (observations) =>
            FlutterForegroundTask.sendDataToMain({
              'status': 'mesh_beacons',
              'beacons': [
                for (final beacon in observations)
                  {
                    'anchorId': beacon.anchorId,
                    'rssi': beacon.rssi,
                    'observedAtMs': beacon.observedAtMs,
                  },
              ],
            }),
        onZoneEstimate: (estimate) => FlutterForegroundTask.sendDataToMain({
          'status': 'mesh_zone',
          'zone': estimate.logicalZone,
          'anchorId': estimate.anchorId,
          'uncertainty': estimate.uncertainty,
        }),
        onCompactSosAlert: _announceCompactSos,
      );
      await controller.start();
      _controller = controller;
      _incomingSubscription = controller.coordinator?.incoming.listen((
        received,
      ) {
        FlutterForegroundTask.sendDataToMain({
          'status': 'mesh_metric',
          'metrics': [
            {
              'kind': 'object_received',
              'peerId': received.peerId,
              'value': received.envelope.payload.length,
              'objectId': received.envelope.objectId,
            },
          ],
        });
        FlutterForegroundTask.sendDataToMain({
          'status': 'mesh_received',
          'received': MeshBridge.receivedToJson(received),
        });
        if (received.envelope.payloadType == PayloadType.structuredSos) {
          unawaited(_announceReceivedSos(received));
        }
      });
      controller.setDebugLossInjection(_debugLossEnabled);
      FlutterForegroundTask.sendDataToMain(const {'status': 'started'});
      if (_sosPending) {
        _sosPending = false;
        unawaited(_sendTestSos(controller));
      }
    } catch (error) {
      FlutterForegroundTask.sendDataToMain({
        'status': 'error',
        'message': error.toString(),
      });
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _incomingSubscription?.cancel();
    _incomingSubscription = null;
    await _controller?.stop();
    _controller = null;
    FlutterForegroundTask.sendDataToMain(const {'status': 'stopped'});
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map && data['debugLoss'] is bool) {
      _debugLossEnabled = data['debugLoss'] as bool;
      _controller?.setDebugLossInjection(_debugLossEnabled);
      return;
    }
    if (data is Map && data['sendMeshObject'] is Map) {
      final envelope = MeshBridge.envelopeFromJson(
        (data['sendMeshObject'] as Map).cast<Object?, Object?>(),
      );
      unawaited(_submitMeshObject(envelope));
      return;
    }
    if (data is Map && data['broadcast_ceal_sos'] == true) {
      final originId = data['originId'] as int?;
      final controller = _controller;
      if (controller != null) {
        unawaited(
          controller.broadcastCompactSos(isTest: false, originId: originId),
        );
        FlutterForegroundTask.sendDataToMain(const {
          'status': 'ceal_sos_broadcast_ok',
        });
      } else {
        FlutterForegroundTask.sendDataToMain(const {
          'status': 'sos_failed',
          'message': 'event mode not ready',
        });
      }
      return;
    }
    if (data != 'send_test_sos') return;
    final controller = _controller;
    if (controller == null) {
      _sosPending = true;
    } else {
      unawaited(_sendTestSos(controller));
    }
  }

  Future<void> _sendTestSos(MeshEventController controller) async {
    try {
      final envelope = await controller.sendTestObject();
      if (envelope == null) {
        FlutterForegroundTask.sendDataToMain(const {'status': 'sos_failed'});
      } else {
        FlutterForegroundTask.sendDataToMain({
          'status': 'mesh_test_origin_submitted',
          'envelope': MeshBridge.envelopeToJson(envelope),
        });
      }
    } catch (error) {
      FlutterForegroundTask.sendDataToMain({
        'status': 'sos_failed',
        'message': error.toString(),
      });
    }
  }

  Future<void> _submitMeshObject(MeshEnvelope envelope) async {
    final controller = _controller;
    if (controller == null || controller.coordinator == null) {
      FlutterForegroundTask.sendDataToMain({
        'status': 'mesh_submit_result',
        'objectId': envelope.objectId,
        'accepted': false,
        'reason': 'event mode is not ready',
      });
      return;
    }
    try {
      if (envelope.payloadType == PayloadType.structuredSos) {
        unawaited(
          controller.broadcastCompactSos(
            originId: envelope.originEphemeralId,
            sequence: envelope.objectId & 0xffff,
          ),
        );
      }
      await controller.coordinator!.send(envelope);
      FlutterForegroundTask.sendDataToMain({
        'status': 'mesh_submit_result',
        'objectId': envelope.objectId,
        'accepted': true,
      });
      if (envelope.payloadType == PayloadType.structuredSos) {
        FlutterForegroundTask.sendDataToMain({
          'status': 'mesh_origin_submitted',
          'envelope': MeshBridge.envelopeToJson(envelope),
        });
      }
    } catch (error) {
      FlutterForegroundTask.sendDataToMain({
        'status': 'mesh_submit_result',
        'objectId': envelope.objectId,
        'accepted': false,
        'reason': '$error',
      });
    }
  }

  void _announceCompactSos(MeshSosAdvertisement alert) {
    _compactAlertKeys.add(alert.dedupeKey);
    unawaited(_showCompactSosNotification(alert));
    // Forward to the UI isolate so MeshBridgeClient can relay to admin backend.
    if (!alert.isTest) {
      FlutterForegroundTask.sendDataToMain({
        'status': 'compact_sos_received',
        'originId': alert.originId,
        'sequence': alert.sequence,
        'siteFingerprint': alert.siteFingerprint,
        'dedupeKey': alert.dedupeKey,
      });
    }
  }

  Future<void> _announceReceivedSos(ReceivedObject received) async {
    final generation = ++_notificationGeneration;
    late final String detail;
    try {
      final sos = StructuredSosPayload.decode(received.envelope.payload);
      final location = sos.latitude == null || sos.longitude == null
          ? 'location unavailable'
          : 'GPS attached';
      final reporter = sos.reporter?.name;
      detail = reporter != null && reporter.isNotEmpty
          ? 'From $reporter · ${sos.triagePriority.name} · $location'
          : 'Priority ${sos.triagePriority.name} · $location';
    } catch (_) {
      // A random/test structured frame is not an SOS notification.
      return;
    }
    final compactKey =
        '${MeshGatt.siteFingerprint(MeshEventController.siteId, namespace: MeshEventController.siteNamespace) & 0xffffffff}:${received.envelope.originEphemeralId & 0xffffffff}:${received.envelope.objectId & 0xffff}';
    if (_compactAlertKeys.remove(compactKey)) return;
    await _showSosNotification(received: received, detail: detail);
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'SOS RECEIVED',
        notificationText: detail,
      );
    } catch (_) {
      // The separate SOS notification above remains the user-visible alert.
    }
    await Future<void>.delayed(const Duration(seconds: 6));
    if (generation != _notificationGeneration) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'MeshSetu event mode active',
        notificationText: 'BLE relay is listening for nearby peers',
      );
    } catch (_) {}
  }
}

/// Port of `in.meshsetu.app.MainActivity` (Kotlin `MainActivity.kt`), plus
/// the Dev B navigation entry point into Join/Rooms/SOS once the mesh is up.
class EventModeScreen extends ConsumerStatefulWidget {
  const EventModeScreen({super.key});

  @override
  ConsumerState<EventModeScreen> createState() => _EventModeScreenState();
}

class _EventModeScreenState extends ConsumerState<EventModeScreen> {
  bool _eventModeActive = false;
  bool _debugLossEnabled = false;
  String _status = 'MeshSetu\nEvent mode is off';
  String _meshStatus = 'stopped';
  String _lastMetric = 'none';
  String _lastConnection = 'none';
  String _nearestBeacon = 'none';
  String _zone = 'unknown';
  String _sttStatus = 'not run';
  bool _sttTesting = false;
  bool _sosPacketSending = false;
  List<Map<String, dynamic>> _peerDebug = const [];
  final Map<String, int> _scanStats = {};
  String _lastReceived = 'none';
  MeshBridgeClient? _bridgeClient;
  late final TextEditingController _adminServerController;
  late final TextEditingController _gatewayKeyController;
  final VoiceRecorder _sttRecorder = VoiceRecorder.withCap(
    const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    _adminServerController = TextEditingController(
      text: ref.read(gatewayUrlProvider),
    );
    _gatewayKeyController = TextEditingController(
      text: ref.read(gatewayDemoKeyProvider),
    );
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _notificationChannelId,
        channelName: 'MeshSetu event mode',
        channelDescription: 'BLE relay and emergency SOS alerts',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
        enableVibration: true,
        playSound: true,
        showWhen: true,
        showBadge: true,
        onlyAlertOnce: false,
      ),
      // iOS isn't a deployment target for this project (Bible §4.1), but the
      // plugin's init call requires this regardless of platform.
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
      ),
    );
    unawaited(_restoreServiceState());
  }

  Future<void> _restoreServiceState() async {
    if (!await FlutterForegroundTask.isRunningService || !mounted) return;
    setState(() {
      _eventModeActive = true;
      _status = 'MeshSetu\nEvent mode active\nBLE relay service running';
    });
    await _startBridgeForActiveSite();
  }

  void _onTaskData(Object data) {
    if (!mounted || data is! Map) return;
    switch (data['status']) {
      case 'started':
        setState(() {
          _eventModeActive = true;
          _status = 'MeshSetu\nEvent mode active\nBLE relay service running';
        });
        unawaited(_startBridgeForActiveSite());
      case 'stopped':
        setState(() {
          _eventModeActive = false;
          _debugLossEnabled = false;
          _meshStatus = 'stopped';
          _peerDebug = const [];
          _nearestBeacon = 'none';
          _zone = 'unknown';
          _scanStats.clear();
          _lastReceived = 'none';
          _lastConnection = 'none';
          _status = 'MeshSetu\nEvent mode is off';
        });
        unawaited(_bridgeClient?.dispose());
        _bridgeClient = null;
        _bridgeClientSiteStarted = false;
      case 'error':
        setState(() {
          _eventModeActive = false;
          _debugLossEnabled = false;
          _status = 'MeshSetu\n${data['message']}';
        });
        unawaited(FlutterForegroundTask.stopService());
      case 'sos_failed':
        setState(() {
          _status =
              'MeshSetu\n${data['message'] ?? 'Test SOS could not queue'}';
        });
      case 'compact_sos_received':
        setState(() {
          _status =
              'MeshSetu\nCompact SOS alert received · forwarding to admin';
        });
      case 'mesh_test_origin_submitted':
        final envelopeJson = data['envelope'];
        if (envelopeJson is Map) {
          unawaited(
            _forwardTestSosToAdmin(
              MeshBridge.envelopeFromJson(
                envelopeJson.cast<Object?, Object?>(),
              ),
            ),
          );
        }
      case 'mesh_status':
        setState(() => _meshStatus = '${data['value'] ?? 'unknown'}');
      case 'mesh_metric':
        final metrics = data['metrics'];
        if (metrics is List) {
          setState(() {
            for (final rawMetric in metrics) {
              if (rawMetric is! Map) continue;
              final metric = Map<String, dynamic>.from(rawMetric);
              final kind = '${metric['kind'] ?? 'unknown'}';
              final value = metric['value'];
              if (kind.startsWith('scan_') && value is num) {
                _scanStats[kind] = value.toInt();
              }
              final peer = metric['peerId'];
              final detail = metric['detail'];
              _lastMetric =
                  '$kind'
                  '${peer == null ? '' : ' ($peer)'}'
                  '${detail == null ? '' : ': $detail'}';
              if (kind == 'peer_connect_failed' ||
                  kind == 'peer_connected' ||
                  kind == 'peer_session_ready' ||
                  kind.startsWith('gatt_') ||
                  kind.startsWith('server_') ||
                  kind == 'send_failed' ||
                  kind == 'control_send_failed') {
                _lastConnection = _lastMetric;
              }
              if (kind == 'object_received') {
                _lastReceived =
                    '${metric['objectId'] ?? '?'} · ${value ?? '?'} bytes'
                    '${peer == null ? '' : ' from $peer'}';
              }
            }
          });
        }
      case 'mesh_peers':
        final peers = data['peers'];
        if (peers is List) {
          setState(
            () => _peerDebug = [
              for (final peer in peers)
                if (peer is Map) Map<String, dynamic>.from(peer),
            ],
          );
        }
      case 'mesh_beacons':
        final beacons = data['beacons'];
        if (beacons is List && beacons.isNotEmpty && beacons.first is Map) {
          final beacon = Map<String, dynamic>.from(beacons.first as Map);
          setState(
            () => _nearestBeacon =
                '${beacon['anchorId']} (${beacon['rssi'] ?? '?'} dBm)',
          );
        } else if (beacons is List && beacons.isEmpty) {
          setState(() => _nearestBeacon = 'none');
        }
      case 'mesh_zone':
        setState(
          () => _zone =
              '${data['zone'] ?? 'unknown'} (${data['uncertainty'] ?? 'unknown'})',
        );
    }
  }

  Future<void> _forwardTestSosToAdmin(MeshEnvelope envelope) async {
    if (!ref.read(gatewayEnabledProvider)) {
      if (mounted) {
        setState(() => _status = 'MeshSetu\nTest SOS sent over BLE only');
      }
      return;
    }
    try {
      final bridge = GatewayBridge(
        baseUrl: Uri.parse(ref.read(gatewayUrlProvider)),
        demoKey: ref.read(gatewayDemoKeyProvider),
      );
      await bridge.postToDashboard(bridge.testSosJson(envelope));
      if (mounted) {
        setState(() => _status = 'MeshSetu\nTest SOS sent to admin server');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'MeshSetu\nAdmin test send failed: $error');
      }
    }
  }

  Future<void> _startEventMode() async {
    if (await FlutterForegroundTask.isRunningService) {
      if (mounted) {
        setState(() {
          _eventModeActive = true;
          _status = 'MeshSetu\nEvent mode active\nBLE relay service running';
        });
      }
      return;
    }
    var startedHere = false;
    try {
      final bluetoothMessage = await BlePermissions.availabilityMessage();
      if (bluetoothMessage != null) {
        if (mounted) setState(() => _status = 'MeshSetu\n$bluetoothMessage');
        return;
      }
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final permissions = await BlePermissions.request(
        sdkInt: androidInfo.version.sdkInt,
      );
      if (permissions.values.any(
        (status) => status != PermissionStatus.granted,
      )) {
        if (mounted) {
          setState(
            () => _status =
                'MeshSetu\nNearby devices permission is required. '
                'Allow Bluetooth access in Settings, then try again.',
          );
        }
        return;
      }

      if (await FlutterForegroundTask.checkNotificationPermission() !=
          NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (await FlutterForegroundTask.checkNotificationPermission() !=
          NotificationPermission.granted) {
        throw StateError('Notification permission is required for event mode');
      }

      final result = await FlutterForegroundTask.startService(
        serviceId: _notificationServiceId,
        notificationTitle: 'MeshSetu event mode active',
        notificationText: 'BLE relay is listening for nearby peers',
        callback: meshEventTaskCallback,
      );
      if (result is! ServiceRequestSuccess) {
        throw StateError('Unable to start the foreground service');
      }
      startedHere = true;

      if (!mounted) return;
      setState(() {
        _eventModeActive = true;
        _status = 'MeshSetu\nStarting BLE relay service';
      });
    } catch (error) {
      if (startedHere) await FlutterForegroundTask.stopService();
      if (mounted) setState(() => _status = 'MeshSetu\n$error');
    }
  }

  Future<void> _stopEventMode() async {
    await FlutterForegroundTask.stopService();
    if (!mounted) return;
    setState(() {
      _eventModeActive = false;
      _debugLossEnabled = false;
      _meshStatus = 'stopped';
      _peerDebug = const [];
      _nearestBeacon = 'none';
      _zone = 'unknown';
      _scanStats.clear();
      _lastConnection = 'none';
      _lastReceived = 'none';
      _status = 'MeshSetu\nEvent mode is off';
    });
  }

  Future<void> _sendTestSos() async {
    setState(() => _status = 'MeshSetu\nTest SOS queued');
    FlutterForegroundTask.sendDataToTask('send_test_sos');
  }

  Future<void> _confirmAndSendSosPacket() async {
    if (_sosPacketSending) return;
    final profile = await ref.read(onboardingRepositoryProvider).load();
    if (!mounted) return;
    if (profile == null) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const OnboardingScreen()));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SosCountdownDialog(),
    );
    if (confirmed == true) await _sendSosPacket();
  }

  Future<void> _sendSosPacket() async {
    setState(() {
      _sosPacketSending = true;
      _status = 'MeshSetu\nPreparing emergency SOS packet…';
    });
    try {
      final site = await ref.read(joinRepositoryProvider).activeManifest();
      final repo = ref.read(sosRepositoryProvider);
      final eventId = await repo.createDraft(
        SosInput(
          siteId: site?.siteId ?? MeshEventController.siteId,
          roomId: site?.rooms.isNotEmpty == true
              ? site!.rooms.first.roomId
              : 'public',
          inputMode: InputMode.tap,
          priority: PriorityBand.p0Critical,
        ),
      );
      final permission = await Permission.locationWhenInUse.request();
      final locationResult = permission.isGranted
          ? await const LocationCapture().capture()
          : const LocationCaptureResult.failure(
              LocationFailureReason.permissionDenied,
            );
      if (locationResult.location case final location?) {
        await repo.attachLocation(eventId, location);
      }
      await repo.finalizeAndEnqueue(eventId);
      if (mounted) {
        setState(() {
          _status =
              'MeshSetu\nSOS packet queued · ${locationResult.status}\n'
              'A real BLE emergency alert will broadcast on mesh submission';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'MeshSetu\nSOS packet failed: $error');
      }
    } finally {
      if (mounted) setState(() => _sosPacketSending = false);
    }
  }

  Future<void> _editProfile() async {
    final profile = await ref.read(onboardingRepositoryProvider).load();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingScreen(initialProfile: profile),
      ),
    );
  }

  Future<void> _confirmAndSendCealSos() async {
    final profile = await ref.read(onboardingRepositoryProvider).load();
    if (!mounted) return;
    if (profile == null) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const OnboardingScreen()));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SosCountdownDialog(),
    );
    if (confirmed != true || !mounted) return;
    setState(
      () => _status = 'MeshSetu\nBroadcasting CEAL-style compact SOS alert…',
    );
    try {
      // Convert the first 4 bytes of the 6-byte reporterUid hex into an int
      // to use as the BLE advertisement originId (CEAL's pseudonymous UID).
      final uidHex = profile.reporterUid.padRight(8, '0').substring(0, 8);
      final originId = int.parse(uidHex, radix: 16);
      FlutterForegroundTask.sendDataToTask({
        'broadcast_ceal_sos': true,
        'originId': originId,
      });
      // Also forward to the admin backend for UID→profile resolution.
      final bridge = _bridgeClient?.gatewayBridge;
      if (bridge != null) {
        bridge.forwardCealSos(
          reporterUid: profile.reporterUid,
          siteId: MeshEventController.siteId,
          originId: originId,
        );
      }
      if (mounted) {
        setState(
          () => _status =
              'MeshSetu\nCEAL-style SOS broadcast sent (UID-only, no payload)\n'
              'Backend will resolve UID→profile if registered',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'MeshSetu\nCEAL SOS broadcast failed: $error');
      }
    }
  }

  Future<void> _openSos() async {
    final site = await ref.read(joinRepositoryProvider).activeManifest();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SosScreen(
          siteId: site?.siteId ?? MeshEventController.siteId,
          roomId: site?.rooms.isNotEmpty == true
              ? site!.rooms.first.roomId
              : 'public',
        ),
      ),
    );
  }

  Future<void> _openJoinOrRooms() async {
    final site = await ref.read(joinRepositoryProvider).activeManifest();
    if (!mounted) return;
    if (site != null) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const RoomsScreen()));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => JoinScreen(
          onJoined: (_) {
            unawaited(_startBridgeForActiveSite());
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const RoomsScreen()),
            );
          },
        ),
      ),
    );
  }

  Future<void> _createEventAndRoom() async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => JoinScreen(
          onJoined: (_) {
            unawaited(_startBridgeForActiveSite());
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const RoomsScreen()),
            );
          },
        ),
      ),
    );
  }

  Future<void> _joinRoomScanQr() async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => JoinScreen(
          onJoined: (roomId) {
            unawaited(_startBridgeForActiveSite());
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const RoomsScreen()),
            );
          },
        ),
      ),
    );
  }

  bool _bridgeClientSiteStarted = false;

  Future<void> _startBridgeForActiveSite() async {
    final site = await ref.read(joinRepositoryProvider).activeManifest();
    if (!mounted || !_eventModeActive) return;
    _bridgeClient ??= MeshBridgeClient(ref.read(databaseProvider));
    if (!_bridgeClientSiteStarted) {
      _bridgeClient!.start(
        siteId: site?.siteId ?? MeshEventController.siteId,
        localEphemeralId: _randomEphemeralId(),
      );
      _bridgeClientSiteStarted = true;
    } else if (site != null) {
      _bridgeClient!.setSiteId(site.siteId);
    }
    _applyGatewaySettings();
  }

  void _applyGatewaySettings() {
    final enabled = ref.read(gatewayEnabledProvider);
    final url = ref.read(gatewayUrlProvider);
    final key = ref.read(gatewayDemoKeyProvider);
    _bridgeClient?.gatewayBridge = (enabled && url.isNotEmpty && key.isNotEmpty)
        ? GatewayBridge(baseUrl: Uri.parse(url), demoKey: key)
        : null;
  }

  int _randomEphemeralId() {
    final random = Random.secure();
    final high = random.nextInt(1 << 31);
    final low = random.nextInt(1 << 32);
    final value = (high << 32) | low;
    return value == 0 ? 1 : value;
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    unawaited(_bridgeClient?.dispose());
    unawaited(_sttRecorder.dispose());
    _adminServerController.dispose();
    _gatewayKeyController.dispose();
    _bridgeClientSiteStarted = false;
    super.dispose();
  }

  Future<void> _runSttSmokeTest() async {
    if (_sttTesting) return;
    setState(() {
      _sttTesting = true;
      _sttStatus = 'recording 3s of raw PCM...';
    });
    try {
      final engine = ref.read(offlineSttEngineProvider);
      await engine.warmUp();
      final pcm = await _sttRecorder.recordPcmClip(
        duration: const Duration(seconds: 3),
      );
      if (!mounted) return;
      setState(() {
        _sttStatus = 'transcribing ${pcm.length} bytes of PCM...';
      });
      final result = await engine.transcribe(pcm);
      if (!mounted) return;
      setState(() {
        _sttStatus =
            'STT ok · "${result.text}" · '
            'conf ${result.confidence.toStringAsFixed(2)} · '
            '${result.modelId}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _sttStatus = 'STT failed: $error');
    } finally {
      if (mounted) setState(() => _sttTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(gatewayEnabledProvider, (_, _) => _applyGatewaySettings());
    ref.listen(gatewayUrlProvider, (_, _) => _applyGatewaySettings());
    ref.listen(gatewayDemoKeyProvider, (_, _) => _applyGatewaySettings());
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_status, style: Theme.of(context).textTheme.headlineSmall),
              StreamBuilder<List<InboxEvent>>(
                stream: ref
                    .read(databaseProvider)
                    .watchInboxSite(MeshEventController.siteId),
                builder: (context, snapshot) {
                  InboxEvent? roomMessage;
                  String? decodedText;
                  for (final row in snapshot.data ?? const <InboxEvent>[]) {
                    if (row.payloadType != PayloadType.roomMessage.name) {
                      continue;
                    }
                    try {
                      decodedText = RoomMessagePacketCodec.decode(
                        siteId: row.siteId,
                        roomId: row.roomId,
                        eventId: row.eventId,
                        packet: row.payload,
                      );
                      roomMessage = row;
                    } catch (_) {
                      // Tampered or incomplete room packets stay hidden.
                    }
                  }
                  if (roomMessage == null || decodedText == null) {
                    return const SizedBox.shrink();
                  }
                  return Card(
                    color: Colors.blue.shade50,
                    child: ListTile(
                      leading: const Icon(
                        Icons.mark_chat_unread,
                        color: Colors.blue,
                      ),
                      title: Text(
                        'Room message received · ${roomMessage.roomId}',
                      ),
                      subtitle: Text(
                        '$decodedText\nFrom: ${roomMessage.peerId}',
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _eventModeActive ? null : _startEventMode,
                child: const Text('Start event mode'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _eventModeActive ? _stopEventMode : null,
                child: const Text('Stop event mode'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _eventModeActive && !_sosPacketSending
                    ? _confirmAndSendSosPacket
                    : null,
                icon: const Icon(Icons.sos),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                label: Text(
                  _sosPacketSending ? 'Queuing SOS packet…' : 'Send SOS packet',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _eventModeActive ? _confirmAndSendCealSos : null,
                icon: const Icon(Icons.cell_tower),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                ),
                label: const Text('Send CEAL-style SOS'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _editProfile,
                icon: const Icon(Icons.badge_outlined),
                label: const Text('Edit emergency profile'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _eventModeActive ? _sendTestSos : null,
                child: const Text('Send BLE SOS notification test'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _eventModeActive ? _openSos : null,
                icon: const Icon(Icons.sos),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                label: const Text('Send real voice + GPS SOS'),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Admin server forwarding'),
                subtitle: const Text(
                  'Send this phone\'s SOS directly to the control room',
                ),
                children: [
                  TextField(
                    controller: _adminServerController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Admin server URL',
                      hintText: 'http://192.168.1.42:8000',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        ref.read(gatewayUrlProvider.notifier).state = value
                            .trim(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _gatewayKeyController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Admin server key',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        ref.read(gatewayDemoKeyProvider.notifier).state = value,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Forward SOS to admin server'),
                    value: ref.watch(gatewayEnabledProvider),
                    onChanged: (value) =>
                        ref.read(gatewayEnabledProvider.notifier).state = value,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: (_eventModeActive && !_sttTesting)
                    ? _runSttSmokeTest
                    : null,
                child: Text(
                  _sttTesting ? 'Running STT test...' : 'Run STT smoke test',
                ),
              ),
              const SizedBox(height: 8),
              Text('STT smoke test: $_sttStatus'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _eventModeActive ? _createEventAndRoom : null,
                icon: const Icon(Icons.add_home_work_outlined),
                style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                label: const Text('Create Event + Room (QR)'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _eventModeActive ? _joinRoomScanQr : null,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Join Room (Scan QR)'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _eventModeActive ? _openJoinOrRooms : null,
                child: const Text('Rooms / Chat / SOS'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Debug: drop/corrupt test frames'),
                value: _debugLossEnabled,
                onChanged: _eventModeActive
                    ? (enabled) {
                        setState(() => _debugLossEnabled = enabled);
                        FlutterForegroundTask.sendDataToTask({
                          'debugLoss': enabled,
                        });
                      }
                    : null,
              ),
              const SizedBox(height: 12),
              Text('Mesh: $_meshStatus · peers: ${_peerDebug.length}'),
              Text(
                'Scan: devices ${_scanStats['scan_devices_seen'] ?? 0} · '
                'service ${_scanStats['scan_service_matches'] ?? 0} · '
                'metadata ${_scanStats['scan_manufacturer_matches'] ?? 0} · '
                'accepted ${_scanStats['scan_peers_accepted'] ?? 0} · '
                'malformed ${_scanStats['scan_malformed_metadata'] ?? 0} · '
                'fingerprint rejected '
                '${_scanStats['scan_fingerprint_mismatches'] ?? 0}',
              ),
              Text('Nearest beacon: $_nearestBeacon'),
              Text('Zone: $_zone'),
              Text('Last metric: $_lastMetric'),
              Text('Connection: $_lastConnection'),
              Text('Last object: $_lastReceived'),
              if (_peerDebug.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final peer in _peerDebug)
                  Text(
                    'Peer ${peer['peerId']}: '
                    '${peer['connected'] == true ? 'connected' : 'disconnected'}, '
                    'MTU ${peer['mtu'] ?? '?'}, '
                    'RSSI ${peer['rssi'] ?? '?'}, '
                    'relay backlog ${peer['queuedObjects'] ?? '?'}',
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SosCountdownDialog extends StatefulWidget {
  const _SosCountdownDialog();

  @override
  State<_SosCountdownDialog> createState() => _SosCountdownDialogState();
}

class _SosCountdownDialogState extends State<_SosCountdownDialog> {
  Timer? _timer;
  var _secondsRemaining = 3;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      setState(() => _secondsRemaining--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.warning_amber_rounded, color: Colors.red),
    title: const Text('Send emergency SOS?'),
    content: Text(
      'Your identity-bound SOS packet will send in $_secondsRemaining '
      '${_secondsRemaining == 1 ? 'second' : 'seconds'}.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
    ],
  );
}
