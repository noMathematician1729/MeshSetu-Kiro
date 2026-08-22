import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/sos_advertisement.dart';
import 'package:meshsetu_mobile/app/sos_incident_navigator.dart';

void main() {
  group('native SOS notification routes', () {
    test('creates and parses an app-owned incident payload', () {
      final payload = SosIncidentNavigator.payloadForEvent('ceal uid/42');

      expect(payload, 'meshsetu://sos/ceal%20uid%2F42');
      expect(SosIncidentNavigator.eventIdFromPayload(payload), 'ceal uid/42');
    });

    test('creates and parses a compact packet payload for offline taps', () {
      const alert = MeshSosAdvertisement(
        siteFingerprint: 1,
        originId: 0x1234,
        sequence: 9,
        flags: MeshSosAdvertisement.alertFlag | (1 << 2),
        ttl: 3,
        reporterUidHex: 'a1b2c3d4e5f6',
      );

      final payload = SosIncidentNavigator.payloadForCompactAlert(alert);
      final decoded = SosIncidentNavigator.compactAlertFromPayload(payload);

      expect(decoded, isNotNull);
      expect(decoded!.dedupeKey, alert.dedupeKey);
      expect(decoded.reporterUidHex, alert.reporterUidHex);
      expect(decoded.emergencyType, SosEmergencyType.fire);
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
