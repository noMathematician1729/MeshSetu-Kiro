import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:meshsetu_mobile/core/data/database.dart';
import 'package:meshsetu_mobile/core/model/model.dart';
import 'package:meshsetu_mobile/feature/onboarding/onboarding_profile.dart';
import 'package:meshsetu_mobile/feature/onboarding/onboarding_repository.dart';
import 'package:meshsetu_mobile/feature/sos/sos_payload.dart';
import 'package:meshsetu_mobile/feature/sos/sos_repository.dart';
import 'package:test/test.dart';

OnboardingProfile sampleProfile() => OnboardingProfile.create(
  profileId: 'profile-1',
  name: 'Asha Patel',
  phone: '+91 98765 43210',
  language: 'English',
  emergencyContacts: const [
    EmergencyContact(name: 'Ravi Patel', phone: '+91 98765 43211'),
  ],
  medicalProfile: const MedicalProfile(
    bloodGroup: 'O+',
    allergies: 'peanuts',
    conditions: 'asthma',
  ),
);

Future<OnboardingRepository> savedRepository() async {
  final repository = OnboardingRepository(MemoryOnboardingStorage());
  await repository.save(sampleProfile());
  return repository;
}

void main() {
  test(
    'onboarding profile persists with a stable pseudonymous reporter UID',
    () async {
      final storage = MemoryOnboardingStorage();
      final repository = OnboardingRepository(storage);
      await repository.save(sampleProfile());
      final first = await repository.load();
      final second = await OnboardingRepository(storage).load();

      expect(first, isNotNull);
      expect(first!.reporterUid, matches(RegExp(r'^[0-9a-f]{12}$')));
      expect(second!.reporterUid, first.reporterUid);
      expect(second.medicalProfile.allergies, 'peanuts');
    },
  );

  test('onboarding profile rejects an SOS-incomplete identity', () async {
    final repository = OnboardingRepository(MemoryOnboardingStorage());
    final invalid = OnboardingProfile.create(
      name: '',
      phone: '12',
      language: '',
      emergencyContacts: const [],
      medicalProfile: const MedicalProfile(),
    );
    expect(() => repository.save(invalid), throwsArgumentError);
  });

  test(
    'structured SOS reporter round-trips and legacy payloads remain valid',
    () {
      const withReporter = StructuredSosPayload(
        incidentType: 'medical',
        transcript: 'help',
        sttConfidence: 0,
        triagePriority: PriorityBand.p0Critical,
        triageConfidence: 0,
        hazards: [],
        rationale: [],
        inputMode: InputMode.tap,
        reporter: SosReporter(
          reporterUid: 'aabbccddeeff',
          name: 'Asha Patel',
          phone: '+919876543210',
          language: 'English',
          bloodGroup: 'O+',
          primaryContactName: 'Ravi Patel',
          primaryContactPhone: '+919876543211',
        ),
      );
      expect(
        StructuredSosPayload.decode(withReporter.encode())
            .reporter
            ?.reporterUid,
        'aabbccddeeff',
      );

      final legacy = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'incidentType': 'other',
            'transcript': '',
            'sttConfidence': 0,
            'triagePriority': 'p1High',
            'triageConfidence': 0,
            'hazards': [],
            'rationale': [],
            'inputMode': 'tap',
          }),
        ),
      );
      expect(StructuredSosPayload.decode(legacy).reporter, isNull);
    },
  );

  test(
    'SOS finalization binds the persisted reporter and requested P0 priority',
    () async {
      final db = MeshDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftSosRepository(db, await savedRepository());
      final eventId = await repository.createDraft(
        const SosInput(
          siteId: 'site',
          roomId: 'public',
          inputMode: InputMode.tap,
          priority: PriorityBand.p0Critical,
        ),
      );
      await repository.finalizeAndEnqueue(eventId);
      final row = await (db.select(
        db.outboxEvents,
      )..where((event) => event.eventId.equals(eventId))).getSingle();
      final payload = StructuredSosPayload.decode(row.payload!);

      expect(payload.triagePriority, PriorityBand.p0Critical);
      expect(payload.reporter?.name, 'Asha Patel');
      expect(payload.reporter?.primaryContactName, 'Ravi Patel');
      expect(payload.reporter?.reporterUid, isNotEmpty);
    },
  );
}
