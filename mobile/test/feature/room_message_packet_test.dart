import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/feature/rooms/room_message_packet.dart';

void main() {
  test('room message packet round trips with HMAC authentication', () {
    final packet = RoomMessagePacketCodec.encode(
      siteId: 'demo-site',
      roomId: 'public',
      eventId: 'event-1',
      text: 'hello mesh',
    );

    expect(
      RoomMessagePacketCodec.decode(
        siteId: 'demo-site',
        roomId: 'public',
        eventId: 'event-1',
        packet: packet,
      ),
      'hello mesh',
    );
  });

  test('room message packet rejects tampering and context swaps', () {
    final packet = RoomMessagePacketCodec.encode(
      siteId: 'demo-site',
      roomId: 'public',
      eventId: 'event-1',
      text: 'original',
    );
    final tampered = Uint8List.fromList(packet)..[8] ^= 1;

    expect(
      () => RoomMessagePacketCodec.decode(
        siteId: 'demo-site',
        roomId: 'public',
        eventId: 'event-1',
        packet: tampered,
      ),
      throwsFormatException,
    );
    expect(
      () => RoomMessagePacketCodec.decode(
        siteId: 'demo-site',
        roomId: 'medical',
        eventId: 'event-1',
        packet: packet,
      ),
      throwsFormatException,
    );
  });
}
