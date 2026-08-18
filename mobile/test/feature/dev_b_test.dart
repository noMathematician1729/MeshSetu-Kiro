import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:meshsetu_mobile/core/data/database.dart';
import 'package:meshsetu_mobile/core/data/outbox_sender.dart';
import 'package:meshsetu_mobile/core/model/model.dart';
import 'package:meshsetu_mobile/app/mesh_bridge.dart';
import 'package:meshsetu_mobile/feature/rooms/room_repository.dart';
import 'package:meshsetu_mobile/feature/join/manifest.dart';
import 'package:meshsetu_mobile/feature/location/location_capture.dart';
import 'package:meshsetu_mobile/feature/rooms/room_policy.dart';
import 'package:meshsetu_mobile/feature/sos/sos_payload.dart';
import 'package:meshsetu_mobile/feature/sos/sos_repository.dart';
import 'package:meshsetu_mobile/feature/triage/triage_engine.dart';
import 'package:meshsetu_mobile/feature/voice/voice_repository.dart';
import 'package:meshsetu_mobile/feature/gateway/gateway_bridge.dart';
import 'package:meshsetu_mobile/feature/join/join_repository.dart';
import 'package:test/test.dart';
import 'dart:typed_data';

void main() {
  test('SafetyRules forces P0 for a critical phrase and defers otherwise', () {
    final rules = SafetyRules();
    expect(
      rules.evaluate('he is not breathing')?.priority,
      PriorityBand.p0Critical,
    );
    expect(
      rules.evaluate('there is smoke everywhere')?.priority,
      PriorityBand.p0Critical,
    );
    expect(rules.evaluate('need a blanket please'), isNull);
  });

  test('TriageEngine falls back conservatively without a classifier', () async {
    final output = await TriageEngine(SafetyRules()).triage('lost my bag');
    expect(output.priority, PriorityBand.p1High);
    expect(output.modelId, 'fallback');
  });

  test('RoomPolicy enforces send/read roles per Bible §10.2', () {
    final medical = policyForRole('medical', 'medical');
    expect(canSend(medical, {'medical'}), isTrue);
    expect(canSend(medical, {'public'}), isFalse);
    expect(canRead(medical, {'authority'}), isTrue);
  });

  test('StructuredSosPayload round trips through JSON encode/decode', () {
    const payload = StructuredSosPayload(
      incidentType: 'medical',
      transcript: 'help',
      sttConfidence: 0.5,
      triagePriority: PriorityBand.p0Critical,
      triageConfidence: 1.0,
      hazards: ['fire'],
      rationale: ['critical safety rule matched'],
      inputMode: InputMode.text,
    );
    final decoded = StructuredSosPayload.decode(payload.encode());
    expect(decoded.incidentType, 'medical');
    expect(decoded.triagePriority, PriorityBand.p0Critical);
    expect(decoded.hazards, ['fire']);
  });

  test(
    'StructuredSosPayload carries GPS and bounds UTF-8 transcript bytes',
    () {
      final payload = StructuredSosPayload(
        incidentType: 'other',
        transcript: '🚨' * 200,
        sttConfidence: 0,
        triagePriority: PriorityBand.p0Critical,
        triageConfidence: 0,
        hazards: const [],
        rationale: const [],
        inputMode: InputMode.voice,
        latitude: 19.076,
        longitude: 72.8777,
        accuracyM: 8.5,
        locationCapturedAtMs: 42,
      );
      final decoded = StructuredSosPayload.decode(payload.encode());
      expect(decoded.transcript.codeUnits.length, lessThan(200));
      expect(decoded.latitude, 19.076);
      expect(decoded.longitude, 72.8777);
      expect(decoded.accuracyM, 8.5);
      expect(decoded.locationCapturedAtMs, 42);
    },
  );

  test('MeshBridge preserves trace IDs across the isolate boundary', () {
    final envelope = MeshEnvelope(
      objectId: 7,
      eventId: 'event',
      siteId: 'site',
      roomId: 'public',
      createdAtMs: 1,
      expiresAtMs: 2,
      hopCount: 0,
      hopLimit: 4,
      priority: PriorityBand.p0Critical,
      payloadType: PayloadType.structuredSos,
      payload: Uint8List.fromList([1]),
      originEphemeralId: 9,
      traceId: Uint8List.fromList(List.generate(16, (i) => i)),
    );
    final decoded = MeshBridge.envelopeFromJson(
      MeshBridge.envelopeToJson(envelope).cast<Object?, Object?>(),
    );
    expect(decoded.traceId, orderedEquals(envelope.traceId));
  });

  test('GatewayBridge maps received SOS location into dashboard JSON', () {
    final envelope = MeshEnvelope(
      objectId: 8,
      eventId: 'sos-event',
      siteId: 'site',
      roomId: 'public',
      createdAtMs: 1,
      expiresAtMs: 2,
      hopCount: 1,
      hopLimit: 4,
      priority: PriorityBand.p0Critical,
      payloadType: PayloadType.structuredSos,
      payload: Uint8List.fromList([1]),
      originEphemeralId: 9,
      traceId: Uint8List(16),
    );
    const sos = StructuredSosPayload(
      incidentType: 'medical',
      transcript: 'help',
      sttConfidence: 1,
      triagePriority: PriorityBand.p0Critical,
      triageConfidence: 1,
      hazards: [],
      rationale: [],
      inputMode: InputMode.voice,
      latitude: 19.076,
      longitude: 72.8777,
      accuracyM: 8.5,
      locationCapturedAtMs: 42,
    );
    final event = GatewayBridge(
      baseUrl: Uri.parse('https://example.test'),
      demoKey: 'test',
    ).eventJson(envelope: envelope, sos: sos);
    expect(event['event_id'], 'sos-event');
    expect(event['latitude'], 19.076);
    expect(event['longitude'], 72.8777);
    expect(event['accuracy_m'], 8.5);
  });

  test('JoinRepository persists a newly created room', () async {
    final db = MeshDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = JoinRepository(db);
    const manifest = EventManifest(
      siteId: 'site',
      siteName: 'Site',
      meshCode: 'CODE',
      validFromMs: 0,
      validUntilMs: 9999999999999,
      gatewayHint: '',
      rooms: [
        RoomManifest(
          roomId: 'public',
          name: 'Public',
          role: 'public',
          ttlSeconds: 3600,
        ),
      ],
    );
    await repository.activateManifest(manifest);
    final updated = await repository.addRoomToActiveManifest(
      const RoomManifest(
        roomId: 'medical-a',
        name: 'Medical A',
        role: 'medical',
        ttlSeconds: 3600,
      ),
    );
    expect(updated.rooms.map((room) => room.roomId), contains('medical-a'));
    expect(
      (await repository.activeManifest())!.rooms.map((room) => room.roomId),
      contains('medical-a'),
    );
  });

  test('local event creation persists a QR-joinable room namespace', () async {
    final db = MeshDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = JoinRepository(db);
    final manifest = await repository.createLocalEvent(
      siteName: 'Safety drill',
    );
    expect(manifest.siteName, 'Safety drill');
    expect(manifest.rooms.single.roomId, 'public');
    final result = await repository.parseAndValidateQr(
      EventManifestCodec.encode(manifest),
    );
    expect(result, isA<JoinOk>());
    expect((result as JoinOk).manifest.siteId, manifest.siteId);
    expect(await repository.activeManifest(), isNotNull);
  });

  test('VoiceObjectPayload rejects tampering before playback', () {
    final payload = VoiceObjectPayload(
      sosEventId: 'sos',
      clipId: 'clip',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    final encoded = payload.encode();
    final tampered = Uint8List.fromList(encoded)..[encoded.length - 2] ^= 1;
    expect(
      () => VoiceObjectPayload.decode(tampered),
      throwsA(isA<FormatException>()),
    );
    expect(VoiceObjectPayload.decode(encoded).bytes, orderedEquals([1, 2, 3]));
  });

  test('EventManifestCodec rejects a tampered manifest', () {
    const manifest = EventManifest(
      siteId: 's',
      siteName: 'Site',
      meshCode: 'ABC123',
      validFromMs: 0,
      validUntilMs: 999999999999,
      rooms: [],
      gatewayHint: '',
    );
    final encoded = EventManifestCodec.encode(manifest);
    final decoded = EventManifestCodec.decode(encoded)!;
    expect(decoded.signatureValid, isTrue);

    final tampered = encoded.replaceFirst('"Site"', '"Evil"');
    final tamperedDecoded = EventManifestCodec.decode(tampered)!;
    expect(tamperedDecoded.signatureValid, isFalse);
  });

  test(
    'DriftSosRepository moves an event through the outbox state machine',
    () async {
      final db = MeshDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DriftSosRepository(db);

      final eventId = await repo.createDraft(
        const SosInput(
          siteId: 'site',
          roomId: 'public',
          inputMode: InputMode.text,
          rawText: 'fire near gate B',
        ),
      );
      var row = await (db.select(
        db.outboxEvents,
      )..where((t) => t.eventId.equals(eventId))).getSingle();
      expect(row.state, 'created');
      expect(row.objectId, isNull);

      final triage = await TriageEngine(SafetyRules()).triage(row.rawText!);
      await repo.attachTriage(eventId, triage);
      await repo.finalizeAndEnqueue(eventId);

      row = await (db.select(
        db.outboxEvents,
      )..where((t) => t.eventId.equals(eventId))).getSingle();
      expect(row.state, 'ready');
      expect(row.objectId, isNotNull);
      expect(row.payload, isNotNull);
      final decoded = StructuredSosPayload.decode(row.payload!);
      expect(decoded.triagePriority, PriorityBand.p0Critical);
    },
  );

  test('triage rationale survives delimiters during persistence', () async {
    final db = MeshDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftSosRepository(db);
    final eventId = await repo.createDraft(
      const SosInput(
        siteId: 'site',
        roomId: 'public',
        inputMode: InputMode.text,
        rawText: 'test',
      ),
    );
    await repo.attachTriage(
      eventId,
      const TriageOutput(
        priority: PriorityBand.p1High,
        incidentType: IncidentType.other,
        confidence: 0.25,
        rationale: ['contains | and ; safely'],
        modelId: 'test',
      ),
    );
    await repo.finalizeAndEnqueue(eventId);
    final row = await (db.select(
      db.outboxEvents,
    )..where((t) => t.eventId.equals(eventId))).getSingle();
    final payload = StructuredSosPayload.decode(row.payload!);
    expect(payload.rationale, ['contains | and ; safely']);
    expect(payload.triageConfidence, 0.25);
  });

  test('SOS location is persisted into the finalized BLE payload', () async {
    final db = MeshDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftSosRepository(db);
    final eventId = await repo.createDraft(
      const SosInput(
        siteId: 'site',
        roomId: 'public',
        inputMode: InputMode.voice,
      ),
    );
    await repo.attachTriage(
      eventId,
      const TriageOutput(
        priority: PriorityBand.p1High,
        incidentType: IncidentType.other,
        confidence: 0,
        rationale: [],
        modelId: 'test',
      ),
    );
    await repo.attachLocation(
      eventId,
      const SosLocation(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracyM: 5,
        capturedAtMs: 100,
      ),
    );
    await repo.finalizeAndEnqueue(eventId);
    final row = await (db.select(
      db.outboxEvents,
    )..where((t) => t.eventId.equals(eventId))).getSingle();
    final payload = StructuredSosPayload.decode(row.payload!);
    expect(payload.triagePriority, PriorityBand.p0Critical);
    expect(payload.latitude, 12.9716);
    expect(payload.longitude, 77.5946);
    expect(payload.accuracyM, 5);
  });

  test('RoomRepository emits a remote message without a local send', () async {
    final db = MeshDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = RoomRepository(db, siteId: 'site');
    final stream = repo.watch('public');
    final message = expectLater(
      stream,
      emitsThrough(
        predicate<List<RoomMessage>>(
          (items) => items.any((item) => item.text == 'remote'),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await db.insertInbox(
      InboxEventsCompanion.insert(
        objectId: const Value(1),
        eventId: 'remote-event',
        siteId: 'site',
        roomId: 'public',
        payloadType: PayloadType.roomMessage.name,
        payload: Uint8List.fromList('remote'.codeUnits),
        peerId: 'peer',
        receivedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await message;
  });

  test('OutboxSender recovers relaying rows after a restart', () async {
    final db = MeshDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.outboxEvents)
        .insert(
          OutboxEventsCompanion.insert(
            eventId: 'event',
            objectId: const Value(11),
            siteId: 'site',
            roomId: 'public',
            payloadType: PayloadType.roomMessage.name,
            priority: PriorityBand.p2Normal.name,
            payload: Value(Uint8List.fromList([1])),
            state: const Value('relaying'),
            createdAtMs: 1,
            updatedAtMs: 1,
            expiresAtMs: DateTime.now().millisecondsSinceEpoch + 60000,
          ),
        );
    final sent = <MeshEnvelope>[];
    final sender = OutboxSender(
      db,
      (envelope) async => sent.add(envelope),
      siteId: 'site',
      localEphemeralId: 3,
    )..start();
    addTearDown(sender.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(sent, hasLength(1));
    expect(sent.single.objectId, 11);
  });
}
