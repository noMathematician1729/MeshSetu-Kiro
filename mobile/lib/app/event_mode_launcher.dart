import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart'
    hide NotificationVisibility;
import 'package:permission_handler/permission_handler.dart';

import '../core/ble/ble_permissions.dart';
import '../core/ble/mesh_radio_preflight.dart';
import 'mesh_event_controller.dart';

const int eventModeNotificationServiceId = 1001;
const String eventModeNotificationChannelId = 'meshsetu-event-v2';
const String meshSiteConfigurationKey = 'mesh-site-configuration';

/// Outcome of one [EventModeLauncher.start] attempt. `alreadyRunning` and
/// `started` both mean the foreground BLE service is now up; the room
/// screens only need to distinguish "keep waiting" (`failure`) from "mesh is
/// live" for their inline banner.
enum EventModeLaunchResult { alreadyRunning, started, failure }

/// Reusable permission-request + foreground-service-start flow, extracted
/// from `event_mode_screen.dart`'s original `_startEventMode` so room
/// screens can prompt the same flow inline (Task 3) instead of forcing the
/// user back to the event-mode screen to discover their message is stuck
/// in the outbox with no mesh service running.
abstract final class EventModeLauncher {
  static var _initialized = false;

  /// Initializes the foreground-task plugin for callers that do not mount
  /// [EventModeScreen] first, such as a participant opening a room directly.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: eventModeNotificationChannelId,
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
      // iOS is not a deployment target, but the plugin requires this option.
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
      ),
    );
  }

  /// Persists the site namespace before startup and forwards it when a task
  /// is already running. The foreground isolate reads this same key during
  /// `onStart` and restarts itself when the site changes.
  static Future<void> configureMeshSite(String siteId) async {
    final configuration = MeshSiteConfiguration.forSite(siteId);
    final encoded = configuration.encode();
    await FlutterForegroundTask.saveData(
      key: meshSiteConfigurationKey,
      value: encoded,
    );
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask({'meshSiteConfiguration': encoded});
    }
  }

  /// Requests Bluetooth/notification permissions (if needed) and starts the
  /// foreground BLE relay service. Safe to call when the service is already
  /// running — returns [EventModeLaunchResult.alreadyRunning] immediately
  /// without re-requesting permissions.
  ///
  /// [taskCallback] is the `@pragma('vm:entry-point')` top-level function
  /// the foreground isolate boots into (`event_mode_screen.meshEventTaskCallback`).
  /// Passed in rather than imported directly to avoid a circular import
  /// between this file and the screen that owns the task handler.
  ///
  /// [onMeshSiteConfigurationNeeded] lets the caller persist the active site
  /// configuration before the service starts, mirroring
  /// `event_mode_screen._saveActiveMeshConfiguration`. Callers that don't
  /// care about site scoping (tests, generic launch) may omit it.
  static Future<EventModeLaunchResult> start({
    required void Function() taskCallback,
    void Function(String message)? onStatus,
    Future<void> Function()? onMeshSiteConfigurationNeeded,
  }) async {
    if (await FlutterForegroundTask.isRunningService) {
      return EventModeLaunchResult.alreadyRunning;
    }
    var startedHere = false;
    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final bluetoothMessage = await BlePermissions.availabilityMessage();
      if (bluetoothMessage != null) {
        onStatus?.call(bluetoothMessage);
        return EventModeLaunchResult.failure;
      }
      final permissions = await BlePermissions.request(
        sdkInt: androidInfo.version.sdkInt,
      );
      if (permissions.values.any(
        (status) => status != PermissionStatus.granted,
      )) {
        onStatus?.call(
          'Nearby devices permission is required. '
          'Allow Bluetooth access in Settings, then try again.',
        );
        return EventModeLaunchResult.failure;
      }
      final preflight = await MeshRadioPreflight.check(
        sdkInt: androidInfo.version.sdkInt,
      );
      if (preflight is MeshRadioBlocked) {
        onStatus?.call(preflight.message);
        return EventModeLaunchResult.failure;
      }

      if (await FlutterForegroundTask.checkNotificationPermission() !=
          NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (await FlutterForegroundTask.checkNotificationPermission() !=
          NotificationPermission.granted) {
        throw StateError('Notification permission is required for event mode');
      }

      await onMeshSiteConfigurationNeeded?.call();

      final result = await FlutterForegroundTask.startService(
        serviceId: eventModeNotificationServiceId,
        notificationTitle: 'MeshSetu event mode active',
        notificationText: 'BLE relay is listening for nearby peers',
        callback: taskCallback,
      );
      if (result is! ServiceRequestSuccess) {
        throw StateError('Unable to start the foreground service');
      }
      startedHere = true;
      return EventModeLaunchResult.started;
    } catch (error) {
      if (startedHere) await FlutterForegroundTask.stopService();
      onStatus?.call('$error');
      return EventModeLaunchResult.failure;
    }
  }
}
