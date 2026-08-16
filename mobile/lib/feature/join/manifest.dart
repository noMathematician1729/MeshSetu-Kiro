import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Bible §9.2 `EventManifest`/`RoomManifest`. The Mesh Code / QR bootstrap
/// identifier for an event/site namespace — not a network root key.
final class EventManifest {
  const EventManifest({
    required this.siteId,
    required this.siteName,
    required this.meshCode,
    required this.validFromMs,
    required this.validUntilMs,
    required this.rooms,
    required this.gatewayHint,
  });

  final String siteId, siteName, meshCode, gatewayHint;
  final int validFromMs, validUntilMs;
  final List<RoomManifest> rooms;
}

final class RoomManifest {
  const RoomManifest({
    required this.roomId,
    required this.name,
    required this.role,
    required this.ttlSeconds,
  });

  final String roomId, name, role;
  final int ttlSeconds;
}

/// Product Rooms are scoped communication channels; this enum is
/// authorization metadata, not a database type.
enum RoomAccess { public, volunteer, medical, responder, authority }

/// Result of validating a scanned/typed join code (Bible §9.3).
sealed class JoinResult {
  const JoinResult();
  factory JoinResult.ok(EventManifest manifest, {String? roomId}) = JoinOk;
  factory JoinResult.invalid(String reason) = JoinInvalid;
}

final class JoinOk extends JoinResult {
  const JoinOk(this.manifest, {this.roomId});
  final EventManifest manifest;
  final String? roomId;
}

final class JoinInvalid extends JoinResult {
  const JoinInvalid(this.reason);
  final String reason;
}

/// Signs/validates and (de)serializes an [EventManifest] to the JSON blob
/// carried in a QR code or resolved from a typed Mesh Code.
///
/// The signing key here is `demoSiteKeyB64`-equivalent: a fixed, publicly
/// known HMAC key compiled only into this hackathon build. It proves the
/// manifest wasn't corrupted/hand-edited in transit, not that it came from a
/// trusted authority — real deployments need a real signing key held only by
/// event organizers. (Bible §9.4 validation checklist.)
abstract final class EventManifestCodec {
  static const String demoSigningKeyB64 = 'meshsetu-demo-manifest-key-v1';

  static String encode(EventManifest manifest, {String? roomId}) {
    final body = _bodyJson(manifest, roomId: roomId);
    final sig = _sign(body);
    return jsonEncode({'body': jsonDecode(body), 'sig': sig});
  }

  static ({EventManifest manifest, bool signatureValid, String? roomId})?
  decode(String raw) {
    try {
      final envelope = jsonDecode(raw) as Map<String, Object?>;
      final body = jsonEncode(envelope['body']);
      final signatureValid = envelope['sig'] == _sign(body);
      final map = envelope['body'] as Map<String, Object?>;
      final manifest = EventManifest(
        siteId: map['siteId'] as String,
        siteName: map['siteName'] as String,
        meshCode: map['meshCode'] as String,
        validFromMs: map['validFromMs'] as int,
        validUntilMs: map['validUntilMs'] as int,
        gatewayHint: map['gatewayHint'] as String? ?? '',
        rooms: [
          for (final r in map['rooms'] as List<Object?>)
            RoomManifest(
              roomId: (r as Map<String, Object?>)['roomId'] as String,
              name: r['name'] as String,
              role: r['role'] as String,
              ttlSeconds: r['ttlSeconds'] as int,
            ),
        ],
      );
      return (
        manifest: manifest,
        signatureValid: signatureValid,
        roomId: map['roomId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  static String _bodyJson(EventManifest m, {String? roomId}) => jsonEncode({
    'siteId': m.siteId,
    'siteName': m.siteName,
    'meshCode': m.meshCode,
    'validFromMs': m.validFromMs,
    'validUntilMs': m.validUntilMs,
    'gatewayHint': m.gatewayHint,
    if (roomId != null) 'roomId': roomId,
    'rooms': [
      for (final r in m.rooms)
        {
          'roomId': r.roomId,
          'name': r.name,
          'role': r.role,
          'ttlSeconds': r.ttlSeconds,
        },
    ],
  });

  static String _sign(String body) => base64Url.encode(
    Hmac(
      sha256,
      Uint8List.fromList(utf8.encode(demoSigningKeyB64)),
    ).convert(utf8.encode(body)).bytes,
  );
}
