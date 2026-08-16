import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../core/data/database.dart';
import 'manifest.dart';

/// Bible §9: resolves a typed Mesh Code or scanned QR payload to a validated
/// [EventManifest] and persists it as the active site (`feature/join`).
class JoinRepository {
  JoinRepository(this._db);

  final MeshDatabase _db;

  /// Demo manifests bundled/preloaded on the app, selected by typed code
  /// (Bible §9.1: "typed code selects a manifest that was bundled/preloaded
  /// on the app"). A real deployment would ship these signed and versioned;
  /// here they're generated on first use with the demo signing key.
  static final Map<String, EventManifest> bundledManifests = {
    'DEMO01': EventManifest(
      siteId: 'demo-site',
      siteName: 'MeshSetu Demo Site',
      meshCode: 'DEMO01',
      validFromMs: 0,
      validUntilMs: DateTime.now().millisecondsSinceEpoch + 86400000 * 365,
      gatewayHint: '',
      rooms: const [
        RoomManifest(
          roomId: 'public',
          name: 'Public Alerts',
          role: 'public',
          ttlSeconds: 86400,
        ),
        RoomManifest(
          roomId: 'gate-b',
          name: 'Zone: Gate-B',
          role: 'volunteer',
          ttlSeconds: 3600,
        ),
        RoomManifest(
          roomId: 'medical',
          name: 'Medical',
          role: 'medical',
          ttlSeconds: 3600,
        ),
        RoomManifest(
          roomId: 'responders',
          name: 'Responders',
          role: 'responder',
          ttlSeconds: 3600,
        ),
      ],
    ),
  };

  Future<JoinResult> parseAndValidateTypedCode(String code) async {
    final manifest = bundledManifests[code.trim().toUpperCase()];
    if (manifest == null) return const JoinInvalid('unknown_code');
    return _activateIfValid(manifest, signatureValid: true);
  }

  Future<JoinResult> parseAndValidateQr(String raw) async {
    final decoded = EventManifestCodec.decode(raw);
    if (decoded == null) return const JoinInvalid('malformed');
    return _activateIfValid(
      decoded.manifest,
      signatureValid: decoded.signatureValid,
    );
  }

  Future<JoinResult> _activateIfValid(
    EventManifest manifest, {
    required bool signatureValid,
  }) async {
    if (!signatureValid) return const JoinInvalid('signature');
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now > manifest.validUntilMs) return const JoinInvalid('expired');
    if (now < manifest.validFromMs) return const JoinInvalid('not_yet_valid');
    await activateManifest(manifest);
    return JoinResult.ok(manifest);
  }

  Future<void> activateManifest(EventManifest manifest) async {
    await _db
        .into(_db.siteManifests)
        .insertOnConflictUpdate(
          SiteManifestsCompanion.insert(
            siteId: manifest.siteId,
            siteName: manifest.siteName,
            meshCode: manifest.meshCode,
            gatewayHint: Value(manifest.gatewayHint),
            validFromMs: manifest.validFromMs,
            validUntilMs: manifest.validUntilMs,
            roomsJson: jsonEncode([
              for (final r in manifest.rooms)
                {
                  'roomId': r.roomId,
                  'name': r.name,
                  'role': r.role,
                  'ttlSeconds': r.ttlSeconds,
                },
            ]),
            joinedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<EventManifest?> activeManifest() async {
    final row = await _db.currentSite();
    if (row == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < row.validFromMs || now > row.validUntilMs) return null;
    final roomsRaw = jsonDecode(row.roomsJson) as List<Object?>;
    return EventManifest(
      siteId: row.siteId,
      siteName: row.siteName,
      meshCode: row.meshCode,
      validFromMs: row.validFromMs,
      validUntilMs: row.validUntilMs,
      gatewayHint: row.gatewayHint ?? '',
      rooms: [
        for (final r in roomsRaw)
          RoomManifest(
            roomId: (r as Map<String, Object?>)['roomId'] as String,
            name: r['name'] as String,
            role: r['role'] as String,
            ttlSeconds: r['ttlSeconds'] as int,
          ),
      ],
    );
  }
}
