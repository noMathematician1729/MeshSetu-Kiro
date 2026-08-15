import 'dart:async';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/ble/ble_permissions.dart';
import 'mesh_event_controller.dart';

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

/// Port of `in.meshsetu.app.MainActivity` (Kotlin `MainActivity.kt`).
class EventModeScreen extends StatefulWidget {
  const EventModeScreen({super.key});

  @override
  State<EventModeScreen> createState() => _EventModeScreenState();
}

class _EventModeScreenState extends State<EventModeScreen> {
  bool _eventModeActive = false;
  bool _debugLossEnabled = false;
  String _status = 'MeshSetu\nEvent mode is off';
  String _meshStatus = 'stopped';
  String _lastMetric = 'none';
  String _nearestBeacon = 'none';
  String _zone = 'unknown';
  List<Map<String, dynamic>> _peerDebug = const [];

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
  }

  void _onTaskData(Object data) {
    if (!mounted || data is! Map) return;
    switch (data['status']) {
      case 'started':
        setState(() {
          _eventModeActive = true;
          _status = 'MeshSetu\nEvent mode active\nBLE relay service running';
        });
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

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
