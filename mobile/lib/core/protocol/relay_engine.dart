import 'dart:io';
import 'dart:typed_data';

import '../model/model.dart';
import 'envelope_codec.dart';
import 'frame.dart';
import 'outbound_scheduler.dart';
import 'secure_envelope.dart';

/// Port of `in.meshsetu.protocol.RelayStore` (Kotlin `RelayEngine.kt`).
///
/// An abstract *class* (not `abstract interface class`) so subclasses can
/// inherit the no-op default bodies, matching Kotlin's `interface { fun f()
/// = default }` methods. Extend this (don't `implements` it), or the
/// defaults won't carry over — Dart's `implements` only takes the member
/// signatures, not their bodies.
abstract class RelayStore {
  void persist(MeshEnvelope envelope);
  bool contains(int objectId) => false;
  void enqueue(EncryptedObject value) {}
  List<EncryptedObject> pending(int nowMs) => const [];
  void markAck(int objectId, String peerId) {}
  void markDeferred(EncryptedObject value) {}
}

class RelayMetric {
  const RelayMetric(
    this.kind, {
    this.objectId,
    this.peerId,
    this.value,
    this.detail,
  });

  final String kind;
  final int? objectId;
  final String? peerId;
  final int? value;
  final String? detail;
}

class RelayResult {
  const RelayResult(this.controlFrames, this.metrics);

  final List<Uint8List> controlFrames;
  final List<RelayMetric> metrics;
}

typedef PersistListener = void Function(MeshEnvelope envelope, String peerId);

const int _maxPartialObjects = 128;
const int _partialTimeoutMs = 30000;
const int _nackDelayMs = 2000;

/// Port of `in.meshsetu.protocol.MeshRelayEngine` (Kotlin `RelayEngine.kt`).
///
/// `receive`/`submit` are `async` here because [CryptoEnvelope] is (see
/// secure_envelope.dart doc comment). Not explicitly locked (see the
/// concurrency note in mesh_transport.dart, which owns serialization).
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
       _onPersist = onPersist ?? ((_, __) {}) {
    final now = clockMs();
    for (final value in store.pending(now)) {
      _knownObjects[value.objectId] = value;
      this.scheduler.enqueue(value, now);
    }
  }

  final String siteId;
  final CryptoEnvelope crypto;
  final RelayStore store;
  final int Function() clockMs;
  final OutboundScheduler scheduler;
  final RecentObjectCache dedupe;
  final PersistListener _onPersist;

  final Map<(String, int), ReassemblyBuffer> _partial = {};
  final Map<(String, int), int> _partialCreatedAt = {};
  final Map<(String, int), int> _lastNackAt = {};
  final Map<int, EncryptedObject> _knownObjects = {};
  final Map<(String, int), int> _inFlight = {};
  final Set<int> _acknowledged = {};
  final List<RelayMetric> _metrics = [];
  final List<PersistListener> _listeners = [];

  void addPersistListener(PersistListener listener) => _listeners.add(listener);

  Future<RelayResult> receive(String peerId, Uint8List encodedFrame) async {
    _cleanupPartial(clockMs());

    final MeshFrame frame;
    try {
      frame = FrameCodec.decode(encodedFrame);
    } catch (_) {
      _metrics.add(RelayMetric('invalid_frame', peerId: peerId));
      return RelayResult(const [], _drain());
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
        return RelayResult(const [], _drain());
      }
      if (_inFlight.remove((peerId, frame.objectId)) != null) {
        _acknowledged.add(frame.objectId);
        store.markAck(frame.objectId, peerId);
        _metrics.add(
          RelayMetric('ack', objectId: frame.objectId, peerId: peerId),
        );
      } else {
        _metrics.add(
          RelayMetric(
            'unexpected_ack',
            objectId: frame.objectId,
            peerId: peerId,
          ),
        );
      }
      return RelayResult(const [], _drain());
    }

    if (frame.type == FrameType.nack) {
      if (frame.payload.isEmpty) {
        _metrics.add(
          RelayMetric('invalid_nack', objectId: frame.objectId, peerId: peerId),
        );
      } else {
        final known = _knownObjects[frame.objectId];
        if (known != null) {
          if (!_acknowledged.contains(frame.objectId)) {
            scheduler.enqueue(known, clockMs());
            _metrics.add(
              RelayMetric(
                'nack_retry',
                objectId: frame.objectId,
                peerId: peerId,
              ),
            );
          }
        } else {
          _metrics.add(
            RelayMetric(
              'unknown_nack',
              objectId: frame.objectId,
              peerId: peerId,
            ),
          );
        }
      }
      return RelayResult(const [], _drain());
    }

    if (frame.type == FrameType.hello) {
      _metrics.add(RelayMetric('hello', peerId: peerId));
      return RelayResult(const [], _drain());
    }

    if (frame.type != FrameType.data) {
      return RelayResult(const [], _drain());
    }

    final key = (peerId, frame.objectId);
    var buffer = _partial[key];
    if (buffer == null) {
      if (_partial.length >= _maxPartialObjects) {
        _metrics.add(
          RelayMetric(
            'reassembly_capacity',
            objectId: frame.objectId,
            peerId: peerId,
          ),
        );
        return RelayResult(const [], _drain());
      }
      buffer = ReassemblyBuffer(frame.count);
      _partial[key] = buffer;
      _partialCreatedAt[key] = clockMs();
    }
    try {
      buffer.add(frame);
    } catch (_) {
      _partial.remove(key);
      _partialCreatedAt.remove(key);
      _lastNackAt.remove(key);
      _metrics.add(
        RelayMetric(
          'reassembly_rejected',
          objectId: frame.objectId,
          peerId: peerId,
        ),
      );
      return RelayResult(const [], _drain());
    }
    if (!buffer.complete()) return RelayResult(const [], _drain());
    _partial.remove(key);
    _partialCreatedAt.remove(key);
    _lastNackAt.remove(key);

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
      return RelayResult(const [], _drain());
    }
    if (envelope.siteId != siteId) {
      _metrics.add(
        RelayMetric('wrong_site', objectId: envelope.objectId, peerId: peerId),
      );
      return RelayResult(const [], _drain());
    }
    final now = clockMs();
    if (envelope.expiresAtMs <= now) {
      _metrics.add(
        RelayMetric('expired', objectId: envelope.objectId, peerId: peerId),
      );
      return RelayResult(const [], _drain());
    }
    if (store.contains(envelope.objectId) ||
        !dedupe.markIfNew(envelope.objectId, envelope.expiresAtMs, now)) {
      _metrics.add(
        RelayMetric('duplicate', objectId: envelope.objectId, peerId: peerId),
      );
      return RelayResult([_ack(frame.objectId, frame.priority)], _drain());
    }

    try {
      store.persist(envelope);
    } catch (_) {
      _metrics.add(
        RelayMetric(
          'persist_failed',
          objectId: envelope.objectId,
          peerId: peerId,
        ),
      );
      return RelayResult(const [], _drain());
    }
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
    _metrics.add(
      RelayMetric(
        'object_latency_ms',
        objectId: envelope.objectId,
        peerId: peerId,
        value: (now - envelope.createdAtMs).clamp(0, 0x7FFFFFFF),
      ),
    );
    if (envelope.hopCount < envelope.hopLimit) {
      final relayed = await crypto.encrypt(
        envelope.copyWith(hopCount: envelope.hopCount + 1),
      );
      _enqueue(relayed, now);
      _metrics.add(
        RelayMetric(
          'relay_enqueued',
          objectId: envelope.objectId,
          peerId: peerId,
        ),
      );
    }
    return RelayResult([_ack(frame.objectId, frame.priority)], _drain());
  }

  EncryptedObject? nextOutbound({int? nowMs}) =>
      scheduler.next(nowMs ?? clockMs());

  void requeue(EncryptedObject value, {int? nowMs}) =>
      _enqueue(value, nowMs ?? clockMs());

  void markSent(EncryptedObject value, String peerId, {int? nowMs}) {
    _knownObjects[value.objectId] = value;
    _inFlight[(peerId, value.objectId)] = nowMs ?? clockMs();
  }

  void retryExpired({int? nowMs, int timeoutMs = 8000}) {
    final now = nowMs ?? clockMs();
    final due = _inFlight.entries
        .where((e) => now - e.value >= timeoutMs)
        .map((e) => e.key)
        .toList();
    for (final key in due) {
      _inFlight.remove(key);
      if (!_acknowledged.contains(key.$2)) {
        final known = _knownObjects[key.$2];
        if (known != null) _enqueue(known, now);
      }
      _metrics.add(
        RelayMetric('ack_timeout', objectId: key.$2, peerId: key.$1),
      );
    }
  }

  void defer(EncryptedObject value) {
    _knownObjects.remove(value.objectId);
    store.markDeferred(value);
  }

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

  List<Uint8List> missingForPeer(
    String peerId, {
    int priority = 3,
    int? nowMs,
  }) {
    final now = nowMs ?? clockMs();
    final results = <Uint8List>[];
    for (final key in _partial.keys.toList()) {
      if (key.$1 != peerId) continue;
      final createdAt = _partialCreatedAt[key] ?? now;
      if (now - createdAt < _nackDelayMs) continue;
      final lastNack = _lastNackAt[key];
      if (lastNack != null && now - lastNack < _nackDelayMs) continue;
      _lastNackAt[key] = now;
      final frame = missing(peerId, key.$2, priority);
      if (frame != null) results.add(frame);
    }
    return results;
  }

  Future<EncryptedObject> submit(MeshEnvelope envelope, {int? nowMs}) async {
    final encrypted = await crypto.encrypt(envelope);
    _enqueue(encrypted, nowMs ?? clockMs());
    return encrypted;
  }

  void _enqueue(EncryptedObject value, int nowMs) {
    _knownObjects[value.objectId] = value;
    store.enqueue(value);
    scheduler.enqueue(value, nowMs);
  }

  void _cleanupPartial(int nowMs) {
    final expired = _partialCreatedAt.entries
        .where((e) => nowMs - e.value >= _partialTimeoutMs)
        .map((e) => e.key)
        .toList();
    for (final key in expired) {
      _partial.remove(key);
      _partialCreatedAt.remove(key);
      _lastNackAt.remove(key);
      _metrics.add(
        RelayMetric('reassembly_timeout', objectId: key.$2, peerId: key.$1),
      );
    }
  }

  List<RelayMetric> drainMetrics() => _drain();

  List<RelayMetric> _drain() {
    final drained = List<RelayMetric>.of(_metrics);
    _metrics.clear();
    return drained;
  }

  static TrafficClass _trafficClassFor(int priority) => switch (priority) {
    1 => TrafficClass.sosStructured,
    2 => TrafficClass.authorityControl,
    3 => TrafficClass.voiceEvidence,
    4 => TrafficClass.roomMessage,
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

/// Port of `in.meshsetu.protocol.FileRelayStore` (Kotlin `RelayEngine.kt`).
///
/// Durable outbox/inbox backed by `dart:io` files under [directory], with
/// the same atomic-write-then-rename pattern as the Kotlin source (write to
/// a `.tmp` file, then rename over the target; rename is atomic on POSIX
/// filesystems when source/target share a directory).
class FileRelayStore extends RelayStore {
  FileRelayStore(this.directory) {
    _inbox.createSync(recursive: true);
    _outbox.createSync(recursive: true);
    Directory('${directory.path}/deferred').createSync(recursive: true);
  }

  final Directory directory;
  Directory get _inbox => Directory('${directory.path}/inbox');
  Directory get _outbox => Directory('${directory.path}/outbox');

  @override
  void persist(MeshEnvelope envelope) => _writeAtomically(
    File('${_inbox.path}/${envelope.objectId}.bin'),
    Uint8List.fromList(EnvelopeCodec.encode(envelope)),
  );

  @override
  bool contains(int objectId) =>
      File('${_inbox.path}/$objectId.bin').existsSync();

  @override
  void enqueue(EncryptedObject value) {
    final out = BytesBuilder();
    out.add(_int64(value.objectId));
    out.add(_int32(value.trafficClass.rank));
    out.add(_int64(value.expiresAtMs));
    out.add(_int64(value.createdAtMs));
    out.add(_int32(value.bytes.length));
    out.add(value.bytes);
    _writeAtomically(
      File('${_outbox.path}/${value.objectId}.bin'),
      out.toBytes(),
    );
  }

  @override
  List<EncryptedObject> pending(int nowMs) {
    final files = _outbox.existsSync() ? _outbox.listSync() : const [];
    final results = <EncryptedObject>[];
    for (final entry in files) {
      if (entry is! File) continue;
      try {
        final bytes = entry.readAsBytesSync();
        final input = ByteData.sublistView(Uint8List.fromList(bytes));
        var offset = 0;
        final objectId = input.getInt64(offset, Endian.big);
        offset += 8;
        final rank = input.getInt32(offset, Endian.big);
        offset += 4;
        final expiresAtMs = input.getInt64(offset, Endian.big);
        offset += 8;
        final createdAtMs = input.getInt64(offset, Endian.big);
        offset += 8;
        final length = input.getInt32(offset, Endian.big);
        offset += 4;
        if (length < 1 || length > maxObjectBytes) continue;
        final payload = Uint8List.sublistView(
          Uint8List.fromList(bytes),
          offset,
          offset + length,
        );
        final trafficClass = TrafficClass.values.firstWhere(
          (t) => t.rank == rank,
        );
        final value = EncryptedObject(
          objectId: objectId,
          trafficClass: trafficClass,
          bytes: payload,
          expiresAtMs: expiresAtMs,
          createdAtMs: createdAtMs,
        );
        if (value.expiresAtMs > nowMs) {
          results.add(value);
        } else {
          entry.deleteSync();
        }
      } catch (_) {
        // Preserve unreadable entries for recovery rather than risking data
        // loss on a transient filesystem failure.
        continue;
      }
    }
    return results;
  }

  @override
  void markAck(int objectId, String peerId) {
    final file = File('${_outbox.path}/$objectId.bin');
    if (file.existsSync()) file.deleteSync();
  }

  @override
  void markDeferred(EncryptedObject value) {
    final outboxFile = File('${_outbox.path}/${value.objectId}.bin');
    if (outboxFile.existsSync()) outboxFile.deleteSync();
    _writeAtomically(
      File('${directory.path}/deferred/${value.objectId}.bin'),
      value.bytes,
    );
  }

  void _writeAtomically(File target, Uint8List bytes) {
    final temp = File('${target.path}.tmp');
    temp.writeAsBytesSync(bytes, flush: true);
    try {
      temp.renameSync(target.path);
    } catch (_) {
      target.writeAsBytesSync(bytes, flush: true);
      if (temp.existsSync()) temp.deleteSync();
    }
  }

  static Uint8List _int64(int value) =>
      (ByteData(8)..setInt64(0, value, Endian.big)).buffer.asUint8List();

  static Uint8List _int32(int value) =>
      (ByteData(4)..setInt32(0, value, Endian.big)).buffer.asUint8List();
}
