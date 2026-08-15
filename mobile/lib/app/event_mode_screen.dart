import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../core/ble/ble_permissions.dart';

const int _notificationServiceId = 1001;
const String _notificationChannelId = 'meshsetu-event';

/// Port of `in.meshsetu.app.MeshEventService` (Kotlin `MeshEventService.kt`)
/// — the foreground-task handler backing the persistent notification.
/// Same scope as the Kotlin service: it keeps the process alive and visible
/// while active-event mode is on. It does not itself drive BLE scanning,
/// advertising, or relay — the Kotlin service didn't either.
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
  bool _eventModeActive = false;

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

    setState(() => _eventModeActive = true);
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
              Text(
                _eventModeActive
                    ? 'MeshSetu\nEvent mode active\nBLE relay service running'
                    : 'MeshSetu\nEvent mode is off',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _eventModeActive ? null : _startEventMode,
                child: const Text('Start event mode'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
