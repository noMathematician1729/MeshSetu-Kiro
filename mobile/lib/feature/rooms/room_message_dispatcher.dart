import 'room_policy.dart';
import 'room_presence_socket.dart';
import 'room_repository.dart';

enum RoomMessageRoute { socket, gatt }

class RoomMessageDelivery {
  const RoomMessageDelivery({required this.eventId, required this.route});

  final String eventId;
  final RoomMessageRoute route;
}

/// Chooses one transport for a room message while retaining the message in
/// Drift until the chosen path has accepted it. A joined socket with another
/// online room member is preferred; every other case enters the durable GATT
/// outbox used by the foreground mesh service.
class RoomMessageDispatcher {
  const RoomMessageDispatcher(this.repository, [this.liveTransport]);

  final RoomRepository repository;
  final LiveRoomMessageTransport? liveTransport;

  Future<RoomMessageDelivery> send({
    required RoomPolicy policy,
    required Set<String> userRoles,
    required String text,
  }) async {
    final live = liveTransport;
    final trySocket = live?.canReachOtherMember ?? false;
    final eventId = await repository.sendMessage(
      policy: policy,
      userRoles: userRoles,
      text: text,
      initialState: trySocket
          ? RoomRepository.socketPendingState
          : RoomRepository.meshReadyState,
    );

    if (!trySocket) {
      return RoomMessageDelivery(
        eventId: eventId,
        route: RoomMessageRoute.gatt,
      );
    }

    final delivered = await live!.sendRoomMessage(
      messageId: eventId,
      text: text.trim(),
    );
    if (delivered) {
      await repository.markSocketDelivered(eventId);
      return RoomMessageDelivery(
        eventId: eventId,
        route: RoomMessageRoute.socket,
      );
    }

    await repository.queueForMesh(eventId);
    return RoomMessageDelivery(eventId: eventId, route: RoomMessageRoute.gatt);
  }
}
