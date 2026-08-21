import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/app/sos_incident_navigator.dart';

void main() {
  group('native SOS notification routes', () {
    test('creates and parses an app-owned incident payload', () {
      final payload = SosIncidentNavigator.payloadForEvent('ceal uid/42');

      expect(payload, 'meshsetu://sos/ceal%20uid%2F42');
      expect(
        SosIncidentNavigator.eventIdFromPayload(payload),
        'ceal uid/42',
      );
    });

    test('rejects old browser links and malformed payloads', () {
      expect(
        SosIncidentNavigator.eventIdFromPayload(
          'https://meshsetu.vercel.app/sos/ceal-1',
        ),
        isNull,
      );
      expect(
        SosIncidentNavigator.eventIdFromPayload('meshsetu://sos/'),
        isNull,
      );
      expect(SosIncidentNavigator.eventIdFromPayload('not a uri'), isNull);
    });
  });
}
