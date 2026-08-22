import 'dart:async';

import 'package:flutter/services.dart';

import '../core/ble/sos_advertisement.dart';

/// Android accessibility-service gesture vocabulary. These values intentionally
/// map only to the typed, structured red-SOS pipeline; they never request the
/// separate CEAL identity/UID compact SOS flow.
enum EmergencyGesture { normal, fire, crime, kidnap, medical, naturalDisaster }

SosEmergencyType? emergencyTypeForGesture(Object? value) => switch (value) {
  'normal' || 'general' => SosEmergencyType.general,
  'fire' => SosEmergencyType.fire,
  'crime' => SosEmergencyType.crime,
  'kidnap' => SosEmergencyType.kidnap,
  'medical' => SosEmergencyType.medical,
  'natural_disaster' => SosEmergencyType.naturalDisaster,
  _ => null,
};

abstract final class EmergencyGestureSettings {
  static const _channel = MethodChannel('meshsetu/emergency-gestures');
  static final _typedSosGestures =
      StreamController<SosEmergencyType>.broadcast();
  static var _isListeningForTypedSosGestures = false;

  /// Typed red-SOS confirmations requested by Android's Accessibility Service.
  /// These values deliberately cannot represent CEAL identity SOS events.
  static Stream<SosEmergencyType> get typedSosGestures =>
      _typedSosGestures.stream;

  /// Installs the UI-engine receiver before asking Android to deliver a pending
  /// gesture. The Android side retains a gesture until this receiver is ready,
  /// which covers both a cold Activity launch and a warm `onNewIntent` launch.
  static void startListeningForTypedSosGestures() {
    if (_isListeningForTypedSosGestures) return;
    _isListeningForTypedSosGestures = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'typedSosGesture') return;
      final emergencyType = emergencyTypeForGesture(call.arguments);
      if (emergencyType != null) _typedSosGestures.add(emergencyType);
    });
    unawaited(_channel.invokeMethod<void>('gestureListenerReady'));
  }

  /// Retrieves a gesture persisted by Android before Flutter's UI receiver was
  /// ready. `take` semantics ensure it cannot generate a second SOS.
  static Future<SosEmergencyType?> takePendingTypedSosGesture() async =>
      emergencyTypeForGesture(
        await _channel.invokeMethod<Object?>('takePendingTypedSosGesture'),
      );

  static Future<bool> isEnabled() async =>
      await _channel.invokeMethod<bool>('isEnabled') ?? false;

  /// Opens Android Accessibility settings. Android requires the user—not an
  /// app—to explicitly enable any global hardware-key listener.
  static Future<void> openSettings() => _channel.invokeMethod('openSettings');
}
