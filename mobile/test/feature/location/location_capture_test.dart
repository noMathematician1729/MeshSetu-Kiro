import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/feature/location/location_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('meshsetu/location');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('parses a native location response', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{
        'ok': true,
        'latitude': 19.076,
        'longitude': 72.8777,
        'accuracyM': 8.5,
        'capturedAtMs': 42,
      };
    });

    final result = await const LocationCapture().capture();

    expect(result.location?.latitude, 19.076);
    expect(result.location?.longitude, 72.8777);
    expect(result.status, 'Location attached');
  });

  test('preserves a native failure reason for the user', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{'ok': false, 'reason': 'services_disabled'};
    });

    final result = await const LocationCapture().capture();

    expect(result.location, isNull);
    expect(result.failure, LocationFailureReason.servicesDisabled);
    expect(result.status, contains('Location services are off'));
  });
}
