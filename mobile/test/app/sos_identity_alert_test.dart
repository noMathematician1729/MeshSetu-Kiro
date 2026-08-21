import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/app/incident_summary.dart';
import 'package:meshsetu_mobile/core/ble/sos_advertisement.dart';

void main() {
  group('compact SOS advertisement identity', () {
    test('carries the reporter UID so a receiver can resolve details', () {
      const alert = MeshSosAdvertisement(
        siteFingerprint: 0x12345678,
        originId: 0x87654321,
        sequence: 7,
        flags: MeshSosAdvertisement.alertFlag,
        ttl: 4,
        reporterUidHex: 'a1b2c3d4e5f6',
      );

      final encoded = alert.encode();
      final decoded = MeshSosAdvertisement.decode(encoded);

      expect(encoded.length, MeshSosAdvertisement.byteLengthWithReporter);
      expect(encoded[0], MeshSosAdvertisement.versionWithReporter);
      expect(decoded, isNotNull);
      expect(decoded!.reporterUidHex, 'a1b2c3d4e5f6');
      expect(decoded.hasReporterUid, isTrue);
      expect(decoded.originId, 0x87654321);
      expect(decoded.sequence, 7);
      expect(decoded.ttl, 4);
    });

    test('stays 14-byte v1 compatible when no UID is known', () {
      const alert = MeshSosAdvertisement(
        siteFingerprint: 9,
        originId: 8,
        sequence: 3,
        flags: MeshSosAdvertisement.alertFlag,
        ttl: 2,
      );

      final encoded = alert.encode();
      final decoded = MeshSosAdvertisement.decode(encoded);

      expect(encoded.length, MeshSosAdvertisement.byteLength);
      expect(encoded[0], MeshSosAdvertisement.version);
      expect(decoded!.hasReporterUid, isFalse);
      expect(decoded.reporterUidHex, isEmpty);
    });

    test('relaying preserves the UID while decrementing TTL', () {
      const alert = MeshSosAdvertisement(
        siteFingerprint: 1,
        originId: 2,
        sequence: 3,
        flags: MeshSosAdvertisement.alertFlag,
        ttl: 4,
        reporterUidHex: '0123456789ab',
      );

      final relayed = MeshSosAdvertisement.decode(
        alert.withTtl(alert.ttl - 1).encode(),
      );

      expect(relayed!.ttl, 3);
      expect(relayed.reporterUidHex, '0123456789ab');
      expect(relayed.dedupeKey, alert.dedupeKey);
    });

    test('rejects a corrupted UID-carrying packet', () {
      const alert = MeshSosAdvertisement(
        siteFingerprint: 4,
        originId: 5,
        sequence: 6,
        flags: MeshSosAdvertisement.alertFlag,
        ttl: 3,
        reporterUidHex: 'ffeeddccbbaa',
      );
      final corrupt = Uint8List.fromList(alert.encode())..[15] ^= 1;

      expect(MeshSosAdvertisement.decode(corrupt), isNull);
    });

    test('normalizes unusable reporter UIDs to empty', () {
      expect(MeshSosAdvertisement.normalizeReporterUid(null), isEmpty);
      expect(MeshSosAdvertisement.normalizeReporterUid('abc'), isEmpty);
      expect(MeshSosAdvertisement.normalizeReporterUid('zzzzzzzzzzzz'), isEmpty);
      expect(MeshSosAdvertisement.normalizeReporterUid('000000000000'), isEmpty);
      expect(
        MeshSosAdvertisement.normalizeReporterUid('A1B2C3D4E5F6'),
        'a1b2c3d4e5f6',
      );
    });
  });

  group('resolved incident presentation', () {
    test('summarizes the dashboard fields a recipient needs', () {
      final summary = describeIncident({
        'reporter_name': 'Priya Sharma',
        'reporter_phone': '+919876543210',
        'incident_type': 'ceal_compact_sos',
        'priority': 'p0Critical',
        'zone': 'Gate-B',
        'latitude': 19.076,
        'longitude': 72.8777,
        'reporter_blood_group': 'O+',
        'transcript': 'I cannot breathe',
      });

      expect(summary, contains('Priya Sharma · +919876543210'));
      expect(summary, contains('ceal compact sos'));
      expect(summary, contains('p0Critical'));
      expect(summary, contains('Gate-B'));
      expect(summary, contains('GPS 19.07600, 72.87770'));
      expect(summary, contains('Blood O+'));
      expect(summary, contains('I cannot breathe'));
      expect(summary, contains('Tap to open'));
    });

    test('omits unresolved fields instead of printing null', () {
      final summary = describeIncident({
        'reporter_name': null,
        'incident_type': 'medical',
        'zone': '',
        'latitude': null,
      });

      expect(summary, isNot(contains('null')));
      expect(summary, contains('medical'));
    });

    test('builds the dedicated incident page link', () {
      expect(
        publicIncidentUrl('https://meshsetu.example/', 'ceal-abc-1'),
        'https://meshsetu.example/sos/ceal-abc-1',
      );
      expect(
        publicIncidentUrl('https://sih26-1xdevs.onrender.com', 'e 1'),
        'https://meshsetu.vercel.app/sos/e%201',
      );
    });
  });
}
