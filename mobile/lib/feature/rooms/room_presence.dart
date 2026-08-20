import 'dart:convert';
import 'dart:typed_data';

final class RoomMember {
  const RoomMember({
    required this.memberId,
    required this.displayName,
    required this.joinedAtMs,
  });

  final String memberId;
  final String displayName;
  final int joinedAtMs;
}

/// Small room-presence payload. Transport encryption authenticates the
/// envelope; this payload identifies a member to the room lobby.
abstract final class RoomPresenceCodec {
  static Uint8List encode(RoomMember member) => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'memberId': member.memberId,
        'displayName': member.displayName,
        'joinedAtMs': member.joinedAtMs,
      }),
    ),
  );

  static RoomMember? decode(Uint8List payload) {
    try {
      final map = jsonDecode(utf8.decode(payload)) as Map<String, Object?>;
      final memberId = map['memberId'] as String? ?? '';
      final displayName = map['displayName'] as String? ?? '';
      final joinedAtMs = map['joinedAtMs'] as int? ?? 0;
      if (map['v'] != 1 ||
          memberId.trim().isEmpty ||
          displayName.trim().isEmpty ||
          joinedAtMs <= 0) {
        return null;
      }
      return RoomMember(
        memberId: memberId,
        displayName: displayName,
        joinedAtMs: joinedAtMs,
      );
    } catch (_) {
      return null;
    }
  }
}
