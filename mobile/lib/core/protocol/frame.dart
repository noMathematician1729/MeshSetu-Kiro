import 'dart:math' as math;
import 'dart:typed_data';

/// Port of `in.meshsetu.protocol` frame layer (Kotlin `Frame.kt`).
///
/// Byte layout is byte-for-byte identical to the Kotlin implementation:
/// `[version:1][type:1][priority:1][flags:1][objectId:8 BE][sequence:2 BE]
/// [count:2 BE][payload...]`. See [model.dart]'s doc comment for how
/// `objectId` (Kotlin `ULong`) maps to a plain Dart `int`.
const int frameHeaderBytes = 16;
const int frameVersion = 1;
const int maxChunks = 512;
const int maxObjectBytes = 64 * 1024;

enum FrameType {
  data(1),
  hello(2),
  custodyAck(3),
  nack(4),
  error(5);

  const FrameType(this.wire);
  final int wire;

  static FrameType? fromWire(int wire) {
    for (final t in FrameType.values) {
      if (t.wire == wire) return t;
    }
    return null;
  }
}

class MeshFrame {
  const MeshFrame({
    required this.type,
    required this.priority,
    required this.flags,
    required this.objectId,
    required this.sequence,
    required this.count,
    required this.payload,
  });

  final FrameType type;
  final int priority;
  final int flags;
  final int objectId;
  final int sequence;
  final int count;
  final Uint8List payload;
}

abstract final class FrameCodec {
  static Uint8List encode(MeshFrame frame) {
    if (frame.priority > 5) throw ArgumentError('priority out of range');
    if (frame.count < 1 || frame.count > maxChunks) {
      throw ArgumentError('count out of range');
    }
    if (frame.sequence >= frame.count) {
      throw ArgumentError('sequence outside chunk count');
    }
    if (frame.payload.length > 0xFFFF) {
      throw ArgumentError('payload too large for uint16 field');
    }
    final out = ByteData(frameHeaderBytes + frame.payload.length);
    out.setUint8(0, frameVersion);
    out.setUint8(1, frame.type.wire);
    out.setUint8(2, frame.priority);
    out.setUint8(3, frame.flags);
    out.setInt64(4, frame.objectId, Endian.big);
    out.setUint16(12, frame.sequence, Endian.big);
    out.setUint16(14, frame.count, Endian.big);
    final bytes = out.buffer.asUint8List();
    bytes.setRange(frameHeaderBytes, bytes.length, frame.payload);
    return bytes;
  }

  static MeshFrame decode(Uint8List bytes) {
    if (bytes.length < frameHeaderBytes) {
      throw ArgumentError('frame is shorter than header');
    }
    final input = ByteData.sublistView(bytes);
    if (input.getUint8(0) != frameVersion) {
      throw ArgumentError('unsupported frame version');
    }
    final type = FrameType.fromWire(input.getUint8(1));
    if (type == null) throw ArgumentError('unknown frame type');
    final priority = input.getUint8(2);
    if (priority > 5) throw ArgumentError('priority out of range');
    final flags = input.getUint8(3);
    final objectId = input.getInt64(4, Endian.big);
    if (objectId == 0) throw ArgumentError('objectId must not be 0');
    final sequence = input.getUint16(12, Endian.big);
    final count = input.getUint16(14, Endian.big);
    if (count < 1 || count > maxChunks) {
      throw ArgumentError('count out of range');
    }
    if (sequence >= count) {
      throw ArgumentError('sequence outside chunk count');
    }
    return MeshFrame(
      type: type,
      priority: priority,
      flags: flags,
      objectId: objectId,
      sequence: sequence,
      count: count,
      payload: Uint8List.sublistView(bytes, frameHeaderBytes),
    );
  }
}

int maxFragmentPayload(int mtu) {
  final attValueBytes = math.max(mtu - 3, 20);
  return math.max(attValueBytes - frameHeaderBytes, 1);
}

List<MeshFrame> fragment({
  required int objectId,
  required int priority,
  required Uint8List encrypted,
  required int mtu,
}) {
  if (objectId == 0) throw ArgumentError('objectId must not be 0');
  if (encrypted.isEmpty || encrypted.length > maxObjectBytes) {
    throw ArgumentError('encrypted object size out of range');
  }
  final size = maxFragmentPayload(mtu);
  final count = (encrypted.length + size - 1) ~/ size;
  if (count < 1 || count > maxChunks) {
    throw ArgumentError('object requires too many chunks');
  }
  return List.generate(count, (index) {
    final start = index * size;
    final end = (start + size < encrypted.length)
        ? start + size
        : encrypted.length;
    return MeshFrame(
      type: FrameType.data,
      priority: priority,
      flags: 0,
      objectId: objectId,
      sequence: index,
      count: count,
      payload: Uint8List.sublistView(encrypted, start, end),
    );
  });
}

class ReassemblyBuffer {
  ReassemblyBuffer(this.expectedCount, {this.maxBytes = maxObjectBytes})
    : _parts = List<Uint8List?>.filled(expectedCount, null) {
    if (expectedCount < 1 || expectedCount > maxChunks) {
      throw ArgumentError('expectedCount out of range');
    }
  }

  final int expectedCount;
  final int maxBytes;
  final List<Uint8List?> _parts;
  int _bytes = 0;
  int _received = 0;

  int get received => _received;

  bool add(MeshFrame frame) {
    if (frame.count != expectedCount ||
        frame.sequence < 0 ||
        frame.sequence >= _parts.length ||
        _parts[frame.sequence] != null) {
      return false;
    }
    if (_bytes + frame.payload.length > maxBytes) {
      throw StateError('reassembly exceeds limit');
    }
    _parts[frame.sequence] = Uint8List.fromList(frame.payload);
    _bytes += frame.payload.length;
    _received++;
    return true;
  }

  bool complete() => _received == expectedCount;

  Uint8List join() {
    if (!complete()) throw StateError('object is incomplete');
    final out = Uint8List(_bytes);
    var offset = 0;
    for (final part in _parts) {
      out.setRange(offset, offset + part!.length, part);
      offset += part.length;
    }
    return out;
  }

  Uint8List missingBitmap() {
    final out = Uint8List((expectedCount + 7) ~/ 8);
    for (var index = 0; index < _parts.length; index++) {
      if (_parts[index] == null) {
        out[index ~/ 8] |= 1 << (index % 8);
      }
    }
    return out;
  }
}
