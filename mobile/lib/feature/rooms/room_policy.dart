import '../../core/model/model.dart';

/// Bible §10.2 Room ACL and transport policy. Membership controls
/// visibility and forwarding; a public participant knowing the event Mesh
/// Code must not automatically read/send restricted-room traffic.
final class RoomPolicy {
  const RoomPolicy({
    required this.roomId,
    required this.sendRoles,
    required this.readRoles,
    required this.trafficClass,
    required this.ttlSeconds,
  });

  final String roomId;
  final Set<String> sendRoles, readRoles;
  final TrafficClass trafficClass;
  final int ttlSeconds;
}

bool canSend(RoomPolicy room, Set<String> userRoles) =>
    room.sendRoles.any(userRoles.contains);

bool canRead(RoomPolicy room, Set<String> userRoles) =>
    room.readRoles.any(userRoles.contains);

/// Bible §10.1 room semantics table, keyed by the `role` string carried in
/// the joined [RoomManifest]. `authority` role implicitly gets every room.
RoomPolicy policyForRole(String roomId, String role, {int ttlSeconds = 3600}) {
  switch (role) {
    case 'public':
      return RoomPolicy(
        roomId: roomId,
        sendRoles: const {'public', 'authority'},
        readRoles: const {
          'public',
          'volunteer',
          'medical',
          'responder',
          'authority',
        },
        trafficClass: TrafficClass.authorityControl,
        ttlSeconds: ttlSeconds,
      );
    case 'medical':
      return RoomPolicy(
        roomId: roomId,
        sendRoles: const {'medical', 'authority'},
        readRoles: const {'medical', 'authority'},
        trafficClass: TrafficClass.roomMessage,
        ttlSeconds: ttlSeconds,
      );
    case 'responder':
      return RoomPolicy(
        roomId: roomId,
        sendRoles: const {'responder', 'authority'},
        readRoles: const {'responder', 'authority'},
        trafficClass: TrafficClass.authorityControl,
        ttlSeconds: ttlSeconds,
      );
    case 'volunteer':
    default:
      return RoomPolicy(
        roomId: roomId,
        sendRoles: const {'volunteer', 'public', 'authority'},
        readRoles: const {'volunteer', 'public', 'authority'},
        trafficClass: TrafficClass.roomMessage,
        ttlSeconds: ttlSeconds,
      );
  }
}
