import 'dart:convert';
import 'dart:typed_data';

import '../core/model/model.dart';

/// Isolated one-packet transport smoke test. This is not the production SOS
/// payload format and must not be decoded as a StructuredSosPayload.
abstract final class TestSosPacket {
  static const message =
      'TEST SOS RECEIVED: MeshSetu emergency link is working.';
  static const payloadLength = 100;

  static Uint8List get payload {
    final messageBytes = Uint8List.fromList(utf8.encode(message));
    if (messageBytes.length > payloadLength) {
      throw StateError('test SOS message exceeds 100-byte payload');
    }
    final result = Uint8List(payloadLength);
    result.fillRange(messageBytes.length, result.length, 0x20);
    result.setRange(0, messageBytes.length, messageBytes);
    return result;
  }

  static bool matches(MeshEnvelope envelope) {
    return matchesPayload(envelope.payloadType, envelope.payload);
  }

  static bool matchesPayload(PayloadType type, List<int> payload) {
    if (type != PayloadType.structuredSos) return false;
    return utf8.decode(payload, allowMalformed: true).trim() == message;
  }
}
