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
      final map = jsonDecode(utf8.decode(payload));
      return map is Map
          ? fromJson(map.cast<String, Object?>(), requireVersion: true)
          : null;
    } catch (_) {
      return null;
    }
  }

  static RoomMember? fromJson(
    Map<String, Object?> map, {
    bool requireVersion = false,
  }) {
    final memberId = map['memberId'] as String? ?? '';
    final displayName = map['displayName'] as String? ?? '';
    final joinedAtMs = (map['joinedAtMs'] as num?)?.toInt() ?? 0;
    if ((requireVersion && map['v'] != 1) ||
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
  }
}
