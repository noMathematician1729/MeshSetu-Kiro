import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../core/data/database.dart';
import '../../core/model/model.dart';
import '../sos/sos_repository.dart';

const _uuid = Uuid();

/// The voice object carries its relationship and digest with the encoded
/// bytes. The mesh treats the payload as opaque, while receivers can reject
/// corrupted audio before writing or playing it.
final class VoiceObjectPayload {
  const VoiceObjectPayload({
    required this.sosEventId,
    required this.clipId,
    required this.bytes,
  });

  final String sosEventId, clipId;
  final Uint8List bytes;

  Uint8List encode() {
    final digest = sha256.convert(bytes).toString();
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'version': 1,
          'sosEventId': sosEventId,
          'clipId': clipId,
          'codec': 'opus',
          'sampleRateHz': 16000,
          'channels': 1,
          'bytes': base64Encode(bytes),
          'sha256': digest,
        }),
      ),
    );
  }

  static VoiceObjectPayload decode(Uint8List encoded) {
    final map = (jsonDecode(utf8.decode(encoded)) as Map)
        .cast<String, Object?>();
    if (map['version'] != 1 || map['codec'] != 'opus') {
      throw const FormatException('unsupported voice payload');
    }
    final sosEventId = map['sosEventId'] as String?;
    final clipId = map['clipId'] as String?;
    if (sosEventId == null ||
        sosEventId.isEmpty ||
        clipId == null ||
        clipId.isEmpty) {
      throw const FormatException('voice payload is missing its event link');
    }
    final bytes = base64Decode(map['bytes'] as String);
    final actual = sha256.convert(bytes).toString();
    if (actual != map['sha256']) {
      throw const FormatException('voice integrity check failed');
    }
    return VoiceObjectPayload(
      sosEventId: sosEventId,
      clipId: clipId,
      bytes: Uint8List.fromList(bytes),
    );
  }
}

/// Bible §3.2 step 2-6: attaches a captured clip to an SOS draft as a
/// separate `VOICE_OBJECT` outbox row (its own state machine, own
/// `voiceEvidence` transport priority) while the structured/transcript
/// object is placed at SOS priority and relayed first — this is why voice
/// is a second row rather than inline bytes on the SOS row.
class VoiceRepository {
  VoiceRepository(this._db, this._sosRepository);

  final MeshDatabase _db;
  final SosRepository _sosRepository;

  Future<String> attachToSos({
    required String sosEventId,
    required String siteId,
    required String roomId,
    required Uint8List encoded,
    int ttlMs = 15 * 60 * 1000,
  }) async {
    if (encoded.isEmpty) throw ArgumentError('voice payload must not be empty');
    final sos = await (_db.select(
      _db.outboxEvents,
    )..where((t) => t.eventId.equals(sosEventId))).getSingleOrNull();
    if (sos == null) throw StateError('SOS draft does not exist');
    await _sosRepository.attachVoice(sosEventId, encoded);
    final clipEventId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db
        .into(_db.outboxEvents)
        .insert(
          OutboxEventsCompanion.insert(
            eventId: clipEventId,
            objectId: Value(_randomObjectId()),
            siteId: siteId,
            roomId: roomId,
            payloadType: PayloadType.voiceObject.name,
            priority:
                PriorityBand.p2Normal.name, // -> TrafficClass.voiceEvidence
            payload: Value(
              VoiceObjectPayload(
                sosEventId: sosEventId,
                clipId: clipEventId,
                bytes: encoded,
              ).encode(),
            ),
            state: const Value('ready'), // queued
            createdAtMs: now,
            updatedAtMs: now,
            expiresAtMs: now + ttlMs,
          ),
        );
    await (_db.update(
      _db.outboxEvents,
    )..where((t) => t.eventId.equals(sosEventId))).write(
      OutboxEventsCompanion(
        voicePath: Value('clip:$clipEventId'),
        updatedAtMs: Value(now),
      ),
    );
    return clipEventId;
  }

  /// queued / transferring / complete / failed, derived from the row's
  /// outbox state machine (Bible §20.5 checklist).
  Stream<String> watchState(String clipEventId) =>
      (_db.select(
        _db.outboxEvents,
      )..where((t) => t.eventId.equals(clipEventId))).watchSingle().map(
        (row) => switch (row.state) {
          'created' || 'ready' => 'queued',
          'relaying' => 'transferring',
          'acked' => 'complete',
          _ => 'failed',
        },
      );

  int _randomObjectId() {
    final random = Random.secure();
    final high = random.nextInt(1 << 31);
    final low = random.nextInt(1 << 32);
    final value = (high << 32) | low;
    return value == 0 ? 1 : value;
  }
}
