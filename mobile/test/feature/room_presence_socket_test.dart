import 'dart:convert';
import 'dart:io';

import 'package:meshsetu_mobile/feature/rooms/room_presence_socket.dart';
import 'package:test/test.dart';

Future<void> _waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test(
    'confirms socket delivery only when a remote member received it',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final webSocket = await WebSocketTransformer.upgrade(request);
        webSocket.listen((raw) {
          final message = jsonDecode(raw as String) as Map<String, Object?>;
          if (message['type'] == 'join-room') {
            webSocket.add(jsonEncode({'type': 'room-joined', 'data': {}}));
            webSocket.add(
              jsonEncode({
                'type': 'room-members',
                'data': [
                  {'memberId': 'self', 'displayName': 'Self', 'joinedAtMs': 1},
                  {'memberId': 'peer', 'displayName': 'Peer', 'joinedAtMs': 2},
                ],
              }),
            );
          } else if (message['type'] == 'room-message') {
            webSocket.add(
              jsonEncode({
                'type': 'room-message-accepted',
                'data': {
                  'messageId': message['messageId'],
                  'recipientCount': 1,
                },
              }),
            );
          }
        });
      });

      final socket = RoomPresenceSocket(
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        gatewayKey: 'key',
        siteId: 'site',
        roomId: 'room',
        memberId: 'self',
        displayName: 'Self',
        messageAckTimeout: const Duration(milliseconds: 200),
      );
      addTearDown(socket.dispose);
      socket.start();
      await _waitUntil(() => socket.canReachOtherMember);

      expect(
        await socket.sendRoomMessage(messageId: 'message', text: 'hello'),
        isTrue,
      );
    },
  );

  test('rejects socket routing when only the sender is online', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final webSocket = await WebSocketTransformer.upgrade(request);
      webSocket.listen((raw) {
        final message = jsonDecode(raw as String) as Map<String, Object?>;
        if (message['type'] != 'join-room') return;
        webSocket.add(jsonEncode({'type': 'room-joined', 'data': {}}));
        webSocket.add(
          jsonEncode({
            'type': 'room-members',
            'data': [
              {'memberId': 'self', 'displayName': 'Self', 'joinedAtMs': 1},
            ],
          }),
        );
      });
    });

    final socket = RoomPresenceSocket(
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      gatewayKey: 'key',
      siteId: 'site',
      roomId: 'room',
      memberId: 'self',
      displayName: 'Self',
    );
    addTearDown(socket.dispose);
    final onlySelf = socket.members.firstWhere(
      (members) => members.length == 1 && members.single.memberId == 'self',
    );
    socket.start();
    await onlySelf;

    expect(
      await socket.sendRoomMessage(messageId: 'message', text: 'offline'),
      isFalse,
    );
  });
}
