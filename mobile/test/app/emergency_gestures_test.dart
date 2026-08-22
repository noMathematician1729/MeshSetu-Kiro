import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/app/emergency_gestures.dart';
import 'package:meshsetu_mobile/core/ble/sos_advertisement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('background typed SOS gestures', () {
    test('maps all six typed emergency gesture events', () {
      const expected = {
        'normal': SosEmergencyType.general,
        'general': SosEmergencyType.general,
        'fire': SosEmergencyType.fire,
        'crime': SosEmergencyType.crime,
        'kidnap': SosEmergencyType.kidnap,
        'medical': SosEmergencyType.medical,
        'natural_disaster': SosEmergencyType.naturalDisaster,
      };
      expected.forEach((gesture, emergencyType) {
        expect(emergencyTypeForGesture(gesture), emergencyType);
      });
    });

    test('does not route CEAL or unknown events through typed SOS', () {
      expect(emergencyTypeForGesture('ceal'), isNull);
      expect(emergencyTypeForGesture('identity_sos'), isNull);
      expect(emergencyTypeForGesture(null), isNull);
    });

    test(
      'forwards a native warm-app gesture to the typed SOS stream',
      () async {
        const channel = MethodChannel('meshsetu/emergency-gestures');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'gestureListenerReady');
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

        final received = EmergencyGestureSettings.typedSosGestures.first;
        EmergencyGestureSettings.startListeningForTypedSosGestures();
        await messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            const MethodCall('typedSosGesture', 'medical'),
          ),
          (_) {},
        );

        expect(await received, SosEmergencyType.medical);
      },
    );
  });
}
