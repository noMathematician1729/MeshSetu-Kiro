import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../core/ble/ble_permissions.dart';
import 'mesh_event_controller.dart';

const int _notificationServiceId = 1001;
const String _notificationChannelId = 'meshsetu-event';

/// Port of `in.meshsetu.app.MeshEventService`'s foreground-service shell
/// (notification/lifecycle only — the actual mesh orchestration lives in
/// [MeshEventController], see its doc comment for why it isn't hosted here
/// in the background task isolate).
@pragma('vm:entry-point')
void meshEventTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_MeshEventTaskHandler());
}

class _MeshEventTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Port of `in.meshsetu.app.MainActivity` (Kotlin `MainActivity.kt`).
class EventModeScreen extends StatefulWidget {
  const EventModeScreen({super.key});

  @override
  State<EventModeScreen> createState() => _EventModeScreenState();
}

class _EventModeScreenState extends State<EventModeScreen> {
  final MeshEventController _controller = MeshEventController();
  bool _eventModeActive = false;
  String _status = 'MeshSetu\nEvent mode is off';

  @override
  void initState() {
    super.initState();
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
  }

  Future<void> _startEventMode() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    await BlePermissions.request(sdkInt: androidInfo.version.sdkInt);

    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    await FlutterForegroundTask.startService(
      serviceId: _notificationServiceId,
      notificationTitle: 'MeshSetu event mode active',
      notificationText: 'BLE relay is listening for nearby peers',
      callback: meshEventTaskCallback,
    );

    await _controller.start();

    setState(() {
      _eventModeActive = true;
      _status = 'MeshSetu\nEvent mode active\nBLE relay service running';
    });
  }

  Future<void> _sendTestSos() async {
    setState(() => _status = 'MeshSetu\nTest SOS queued');
    await _controller.sendTestObject();
  }

  @override
  void dispose() {
    unawaited(_controller.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
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
                onPressed: _eventModeActive ? _sendTestSos : null,
                child: const Text('Send 100-byte test SOS'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
