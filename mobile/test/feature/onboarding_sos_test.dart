import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:meshsetu_mobile/core/data/database.dart';
import 'package:meshsetu_mobile/core/model/model.dart';
import 'package:meshsetu_mobile/feature/onboarding/onboarding_profile.dart';
import 'package:meshsetu_mobile/feature/onboarding/onboarding_repository.dart';
import 'package:meshsetu_mobile/feature/sos/sos_payload.dart';
import 'package:meshsetu_mobile/feature/sos/sos_repository.dart';
import 'package:meshsetu_mobile/feature/voice/voice_repository.dart';
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

  test('onboarding stores canonical E.164 phone numbers', () async {
    final profile = OnboardingProfile.create(
      profileId: 'e164-profile',
      name: 'Asha Patel',
      phone: '+91 (98765) 43210',
      language: 'English',
      emergencyContacts: const [
        EmergencyContact(name: 'Ravi Patel', phone: '+91 98765-43211'),
      ],
      medicalProfile: const MedicalProfile(),
    );

    expect(profile.phone, '+919876543210');
    expect(profile.emergencyContacts.single.phone, '+919876543211');
    expect(profile.validationError, isNull);

    final repository = OnboardingRepository(MemoryOnboardingStorage());
    await repository.save(profile);
    final persisted = await repository.load();
    expect(persisted!.phone, '+919876543210');
    expect(persisted.emergencyContacts.single.phone, '+919876543211');
  });

  test(
    'onboarding rejects emergency contacts without an E.164 country code',
    () {
      final profile = OnboardingProfile.create(
        profileId: 'local-contact-profile',
        name: 'Asha Patel',
        phone: '+919876543210',
        language: 'English',
        emergencyContacts: const [
          EmergencyContact(name: 'Ravi Patel', phone: '9876543211'),
        ],
        medicalProfile: const MedicalProfile(),
      );

      expect(profile.validationError, contains('E.164'));
    },
  );

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
        StructuredSosPayload.decode(
          withReporter.encode(),
        ).reporter?.reporterUid,
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

  test(
    'voice evidence is linked before the structured SOS is queued',
    () async {
      final db = MeshDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final sosRepository = DriftSosRepository(db, await savedRepository());
      final eventId = await sosRepository.createDraft(
        const SosInput(
          siteId: 'site',
          roomId: 'public',
          inputMode: InputMode.voice,
          priority: PriorityBand.p0Critical,
        ),
      );
      await VoiceRepository(db, sosRepository).attachToSos(
        sosEventId: eventId,
        siteId: 'site',
        roomId: 'public',
        encoded: Uint8List.fromList([1, 2, 3]),
      );
      await sosRepository.finalizeAndEnqueue(eventId);

      final rows = await db.select(db.outboxEvents).get();
      final sos = rows.singleWhere((row) => row.eventId == eventId);
      final voice = rows.singleWhere(
        (row) => row.payloadType == PayloadType.voiceObject.name,
      );
      expect(
        StructuredSosPayload.decode(sos.payload!).voiceClipId,
        voice.eventId,
      );
      expect(sos.state, 'ready');
      expect(voice.state, 'ready');
    },
  );
}
