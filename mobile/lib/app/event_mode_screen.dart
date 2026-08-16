import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/ble/ble_permissions.dart';
import '../core/model/model.dart';
import '../feature/gateway/gateway_bridge.dart';
import '../feature/join/manifest.dart';
import '../feature/join/join_screen.dart';
import '../feature/rooms/rooms_screen.dart';
import '../feature/rooms/room_chat_screen.dart';
import '../feature/voice/voice_recorder.dart';
import 'mesh_bridge.dart';
import 'mesh_bridge_client.dart';
import 'mesh_event_controller.dart';
import 'providers.dart';

const int _notificationServiceId = 1001;
const String _notificationChannelId = 'meshsetu-event';

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
      );
      await controller.start();
      _controller = controller;
      _incomingSubscription = controller.coordinator?.incoming.listen((
        received,
      ) {
        FlutterForegroundTask.sendDataToMain({
          'status': 'mesh_received',
          'received': MeshBridge.receivedToJson(received),
        });
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
      unawaited(_submitMeshObject(envelope, data['objectId']));
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

  Future<void> _submitMeshObject(
    MeshEnvelope envelope,
    Object? requestId,
  ) async {
    final objectId = requestId is int ? requestId : envelope.objectId;
    try {
      final controller = _controller;
      final coordinator = controller?.coordinator;
      if (controller == null || coordinator == null) {
        throw StateError('mesh service is not ready');
      }
      if (envelope.siteId != MeshEventController.siteId) {
        throw StateError('object belongs to a different event site');
      }
      await coordinator.send(envelope);
      FlutterForegroundTask.sendDataToMain({
        'status': 'mesh_submit_result',
        'objectId': objectId,
        'accepted': true,
      });
    } catch (error) {
      FlutterForegroundTask.sendDataToMain({
        'status': 'mesh_submit_result',
        'objectId': objectId,
        'accepted': false,
        'reason': error.toString(),
      });
    }
  }

  Future<void> _sendTestSos(MeshEventController controller) async {
    try {
      if (!await controller.sendTestObject()) {
        FlutterForegroundTask.sendDataToMain(const {'status': 'sos_failed'});
      }
    } catch (error) {
      FlutterForegroundTask.sendDataToMain({
        'status': 'sos_failed',
        'message': error.toString(),
      });
    }
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
  String _nearestBeacon = 'none';
  String _zone = 'unknown';
  String _sttStatus = 'not run';
  bool _sttTesting = false;
  List<Map<String, dynamic>> _peerDebug = const [];
  MeshBridgeClient? _bridgeClient;
  final VoiceRecorder _sttRecorder = VoiceRecorder.withCap(
    const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _notificationChannelId,
        channelName: 'MeshSetu event mode',
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
      case 'mesh_status':
        setState(() => _meshStatus = '${data['value'] ?? 'unknown'}');
      case 'mesh_submit_result':
        setState(
          () => _lastMetric = data['accepted'] == true
              ? 'mesh accepted object ${data['objectId']}'
              : 'mesh rejected object ${data['objectId']}',
        );
      case 'mesh_received':
        final receivedJson = data['received'];
        if (receivedJson is! Map) return;
        final received = MeshBridge.receivedFromJson(
          receivedJson.cast<Object?, Object?>(),
        );
        if (received.envelope.payloadType == PayloadType.structuredSos) {
          final message = utf8
              .decode(received.envelope.payload, allowMalformed: true)
              .trim();
          if (message == MeshEventController.testSosMessage) {
            setState(() {
              _status = 'MeshSetu\n$message';
              _lastMetric = 'test SOS received from ${received.peerId}';
            });
          }
        }
      case 'mesh_metric':
        final metrics = data['metrics'];
        if (metrics is List && metrics.isNotEmpty && metrics.first is Map) {
          final metric = Map<String, dynamic>.from(metrics.first as Map);
          setState(
            () => _lastMetric =
                '${metric['kind']}${metric['peerId'] == null ? '' : ' (${metric['peerId']})'}',
          );
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

  Future<void> _startEventMode() async {
    if (await FlutterForegroundTask.isRunningService) {
      if (mounted) {
        setState(() {
          _eventModeActive = true;
          _status = 'MeshSetu\nEvent mode active\nBLE relay service running';
        });
      }
      await _startBridgeForActiveSite();
      return;
    }
    var startedHere = false;
    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final permissions = await BlePermissions.request(
        sdkInt: androidInfo.version.sdkInt,
      );
      if (permissions.values.any(
        (status) => status != PermissionStatus.granted,
      )) {
        throw StateError('Bluetooth permissions are required for event mode');
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
      _status = 'MeshSetu\nEvent mode is off';
    });
  }

  Future<void> _sendTestSos() async {
    setState(() => _status = 'MeshSetu\nTest SOS queued');
    FlutterForegroundTask.sendDataToTask('send_test_sos');
  }

  Future<void> _openJoinOrRooms() async {
    final site = await ref.read(joinRepositoryProvider).activeManifest();
    if (!mounted) return;
    if (site != null) {
      unawaited(_startBridgeForActiveSite());
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const RoomsScreen()));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => JoinScreen(
          onJoined: (roomId) async {
            unawaited(_startBridgeForActiveSite());
            final joinedSite = await ref
                .read(joinRepositoryProvider)
                .activeManifest();
            if (!mounted || !context.mounted || joinedSite == null) return;
            RoomManifest? room;
            if (roomId != null) {
              for (final candidate in joinedSite.rooms) {
                if (candidate.roomId == roomId) {
                  room = candidate;
                  break;
                }
              }
            }
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => room == null
                    ? const RoomsScreen()
                    : RoomChatScreen(
                        siteId: joinedSite.siteId,
                        roomId: room.roomId,
                        roomName: room.name,
                        role: room.role,
                      ),
              ),
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
    _bridgeClientSiteStarted = false;
    super.dispose();
  }

  Future<void> _runFakeSttSmokeTest() async {
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
      setState(() => _sttStatus = 'fake STT failed: $error');
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
              FilledButton(
                onPressed: _eventModeActive ? _sendTestSos : null,
                child: const Text('Send 100-byte test SOS'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: (_eventModeActive && !_sttTesting)
                    ? _runFakeSttSmokeTest
                    : null,
                child: Text(
                  _sttTesting ? 'Running STT test...' : 'Run STT smoke test',
                ),
              ),
              const SizedBox(height: 8),
              Text('STT smoke test: $_sttStatus'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _eventModeActive ? _openJoinOrRooms : null,
                child: const Text('Join event / Rooms / SOS'),
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
              Text('Nearest beacon: $_nearestBeacon'),
              Text('Zone: $_zone'),
              Text('Last metric: $_lastMetric'),
              if (_peerDebug.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final peer in _peerDebug)
                  Text(
                    'Peer ${peer['peerId']}: '
                    '${peer['connected'] == true ? 'connected' : 'disconnected'}, '
                    'MTU ${peer['mtu'] ?? '?'}, '
                    'RSSI ${peer['rssi'] ?? '?'}, '
                    'queued ${peer['queuedObjects'] ?? '?'}',
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
