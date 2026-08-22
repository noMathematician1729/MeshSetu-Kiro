import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Tells the foreground BLE task which room chat screen (if any) the user is
/// currently viewing, so the task can suppress notifications for that room.
///
/// The reporter is intentionally thin: it only sends a message to the task
/// isolate via [FlutterForegroundTask.sendDataToTask] and keeps the last
/// value to avoid redundant sends. The task handler stores the result in its
/// own `_activeRoomId` field.
///
/// [sendToTask] is injectable for unit tests — production callers omit it
/// and the default uses [FlutterForegroundTask.sendDataToTask].
class ActiveRoomReporter {
  ActiveRoomReporter({
    required this.roomId,
    void Function(Object data)? sendToTask,
  }) : _send = sendToTask ?? FlutterForegroundTask.sendDataToTask;

  final String roomId;
  final void Function(Object data) _send;

  /// Distinct sentinel meaning "never reported anything yet".
  static const _notYetReported = Object();
  Object? _lastReported = _notYetReported;

  /// Reports [roomId] as the active room. Safe to call multiple times; sends
  /// only when the value changes.
  void reportActive() => _report(roomId);

  /// Reports that no room is currently visible. Safe to call multiple times.
  void reportInactive() => _report(null);

  void _report(String? value) {
    if (!identical(_lastReported, _notYetReported) && _lastReported == value) {
      return;
    }
    _lastReported = value;
    _send({'active_room': value});
  }
}
