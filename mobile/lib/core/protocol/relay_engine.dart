import 'dart:typed_data';

import '../model/model.dart';
import 'frame.dart';
import 'outbound_scheduler.dart';
import 'secure_envelope.dart';

/// Port of `in.meshsetu.protocol.MeshRelayEngine` (Kotlin `RelayEngine.kt`).
///
/// `receive` and `submit` are `async` here because [CryptoEnvelope] is
/// `async` in this port (see secure_envelope.dart doc comment).
///
/// The Kotlin methods are `@Synchronized`; this port does not add an
/// explicit lock. Dart's single-isolate event loop means there's no
/// preemptive-thread race, but an `await` inside `receive`/`submit` can
/// still let another call interleave. That's fine for this port's scope
/// (sequential unit tests, matching the Kotlin test suite); a real
/// multi-peer transport coordinator should serialize calls per peer/object
/// itself (this is what `MeshTransportCoordinator`'s `pumpLock` did in the
/// Kotlin `core-ble` layer, which sub-project 2 will need to replicate).
abstract interface class RelayStore {
  void persist(MeshEnvelope envelope);
}

class RelayMetric {
  const RelayMetric(this.kind, {this.objectId, this.peerId, this.value});

  final String kind;
  final int? objectId;
  final String? peerId;
  final int? value;
}

class RelayResult {
  const RelayResult(this.controlFrames, this.metrics);

  final List<Uint8List> controlFrames;
  final List<RelayMetric> metrics;
}

typedef PersistListener = void Function(MeshEnvelope envelope, String peerId);

class MeshRelayEngine {
  MeshRelayEngine({
    required this.siteId,
    required this.crypto,
    required this.store,
    required this.clockMs,
    OutboundScheduler? scheduler,
    RecentObjectCache? dedupe,
    PersistListener? onPersist,
  }) : scheduler = scheduler ?? OutboundScheduler(),
       dedupe = dedupe ?? RecentObjectCache(),
       _onPersist = onPersist ?? ((_, __) {});

  final String siteId;
  final CryptoEnvelope crypto;
  final RelayStore store;
  final int Function() clockMs;
  final OutboundScheduler scheduler;
  final RecentObjectCache dedupe;
  final PersistListener _onPersist;

  final Map<(String, int), ReassemblyBuffer> _partial = {};
  final List<RelayMetric> _metrics = [];
  final List<PersistListener> _listeners = [];

  void addPersistListener(PersistListener listener) => _listeners.add(listener);

  Future<RelayResult> receive(String peerId, Uint8List encodedFrame) async {
    final MeshFrame frame;
    try {
      frame = FrameCodec.decode(encodedFrame);
    } catch (_) {
      _metrics.add(RelayMetric('invalid_frame', peerId: peerId));
      return RelayResult(const [], _drainMetrics());
    }

    if (frame.type == FrameType.custodyAck) {
      final matches =
          frame.payload.length == 8 &&
          ByteData.sublistView(frame.payload).getInt64(0, Endian.big) ==
              frame.objectId;
      if (!matches) {
        _metrics.add(
          RelayMetric('invalid_ack', objectId: frame.objectId, peerId: peerId),
        );
        return RelayResult(const [], _drainMetrics());
      }
      _metrics.add(
        RelayMetric('ack', objectId: frame.objectId, peerId: peerId),
      );
      return RelayResult(const [], _drainMetrics());
    }

    if (frame.type != FrameType.data) {
      return RelayResult(const [], _drainMetrics());
    }

    final key = (peerId, frame.objectId);
    final buffer = _partial.putIfAbsent(
      key,
      () => ReassemblyBuffer(frame.count),
    );
    try {
      buffer.add(frame);
    } catch (_) {
      _partial.remove(key);
      _metrics.add(
        RelayMetric(
          'reassembly_rejected',
          objectId: frame.objectId,
          peerId: peerId,
        ),
      );
      return RelayResult(const [], _drainMetrics());
    }
    if (!buffer.complete()) return RelayResult(const [], _drainMetrics());
    _partial.remove(key);

    final encrypted = EncryptedObject(
      objectId: frame.objectId,
      trafficClass: _trafficClassFor(frame.priority),
      bytes: buffer.join(),
      expiresAtMs: _maxInt,
    );
    final envelope = await crypto.decrypt(encrypted);
    if (envelope == null) {
      _metrics.add(
        RelayMetric('invalid_object', objectId: frame.objectId, peerId: peerId),
      );
      return RelayResult(const [], _drainMetrics());
    }
    if (envelope.siteId != siteId) {
      _metrics.add(
        RelayMetric('wrong_site', objectId: envelope.objectId, peerId: peerId),
      );
      return RelayResult(const [], _drainMetrics());
    }
    final now = clockMs();
    if (envelope.expiresAtMs <= now) {
      _metrics.add(
        RelayMetric('expired', objectId: envelope.objectId, peerId: peerId),
      );
      return RelayResult(const [], _drainMetrics());
    }
    if (!dedupe.markIfNew(envelope.objectId, envelope.expiresAtMs, now)) {
      _metrics.add(
        RelayMetric('duplicate', objectId: envelope.objectId, peerId: peerId),
      );
      return RelayResult([
        _ack(frame.objectId, frame.priority),
      ], _drainMetrics());
    }

    store.persist(envelope);
    _onPersist(envelope, peerId);
    for (final listener in _listeners) {
      listener(envelope, peerId);
    }
    _metrics.add(
      RelayMetric(
        'object_complete',
        objectId: envelope.objectId,
        peerId: peerId,
        value: envelope.hopCount,
      ),
    );
    if (envelope.hopCount < envelope.hopLimit) {
      final relayed = await crypto.encrypt(
        envelope.copyWith(hopCount: envelope.hopCount + 1),
      );
      scheduler.enqueue(relayed, now);
      _metrics.add(
        RelayMetric(
          'relay_enqueued',
          objectId: envelope.objectId,
          peerId: peerId,
        ),
      );
    }
    return RelayResult([_ack(frame.objectId, frame.priority)], _drainMetrics());
  }

  EncryptedObject? nextOutbound({int? nowMs}) =>
      scheduler.next(nowMs ?? clockMs());

  void requeue(EncryptedObject value, {int? nowMs}) =>
      scheduler.enqueue(value, nowMs ?? clockMs());

  Uint8List? missing(String peerId, int objectId, int priority) {
    final buffer = _partial[(peerId, objectId)];
    if (buffer == null) return null;
    return FrameCodec.encode(
      MeshFrame(
        type: FrameType.nack,
        priority: priority,
        flags: 0,
        objectId: objectId,
        sequence: 0,
        count: 1,
        payload: buffer.missingBitmap(),
      ),
    );
  }

  Future<EncryptedObject> submit(MeshEnvelope envelope, {int? nowMs}) async {
    final encrypted = await crypto.encrypt(envelope);
    scheduler.enqueue(encrypted, nowMs ?? clockMs());
    return encrypted;
  }

  List<RelayMetric> _drainMetrics() {
    final drained = List<RelayMetric>.of(_metrics);
    _metrics.clear();
    return drained;
  }

  static TrafficClass _trafficClassFor(int priority) => switch (priority) {
    1 => TrafficClass.sosStructured,
    2 => TrafficClass.authorityControl,
    3 => TrafficClass.roomMessage,
    _ => TrafficClass.telemetry,
  };

  static Uint8List _ack(int objectId, int priority) {
    final payload = ByteData(8)..setInt64(0, objectId, Endian.big);
    return FrameCodec.encode(
      MeshFrame(
        type: FrameType.custodyAck,
        priority: priority,
        flags: 0,
        objectId: objectId,
        sequence: 0,
        count: 1,
        payload: payload.buffer.asUint8List(),
      ),
    );
  }
}

// Matches Kotlin's `Long.MAX_VALUE` sentinel used for reassembly-scratch
// EncryptedObjects that are immediately consumed by crypto.decrypt and never
// scheduled (so their expiry is irrelevant).
const int _maxInt = 0x7FFFFFFFFFFFFFFF;
