import 'dart:async';

import 'package:drift/drift.dart';

import '../model/model.dart';
import '../protocol/relay_engine.dart';
import 'database.dart';

/// Drains `state = ready` [OutboxEvents] rows through a caller-supplied
/// `send` callback and reflects ACK/expiry metrics back onto the row,
/// implementing the CREATED -> READY -> RELAYING -> ACKED|EXPIRED state
/// machine from Bible §2.5. Shared by `feature/sos` and `feature/rooms` —
/// both just insert a `ready` row and this drains it.
///
/// `send` is a callback rather than a direct `MeshTransportCoordinator`
/// reference because the coordinator lives in the `flutter_foreground_task`
/// background isolate (`app/mesh_event_controller.dart`), not the UI
/// isolate this repository runs in — `app/mesh_bridge.dart` wires the two
/// together over the plugin's isolate message channel.
class OutboxSender {
  OutboxSender(
    this._db,
    this._send, {
    required this.siteId,
    required this.localEphemeralId,
  });

  final MeshDatabase _db;
  final Future<void> Function(MeshEnvelope envelope) _send;
  final String siteId;
  final int localEphemeralId;

  StreamSubscription<List<OutboxEvent>>? _sub;
  final Set<String> _draining = {};
  final Map<String, Timer> _retryTimers = {};
  bool _disposed = false;

  void start() {
    _disposed = false;
    unawaited(_recoverAndListen());
  }

  Future<void> _recoverAndListen() async {
    await (_db.update(
          _db.outboxEvents,
        )..where((t) => (t.siteId.equals(siteId) & t.state.equals('relaying'))))
        .write(
          OutboxEventsCompanion(
            state: const Value('ready'),
            updatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
    if (_disposed) return;
    _sub = _db.watchReady(siteId).listen((rows) {
      for (final row in rows) {
        if (_draining.add(row.eventId)) unawaited(_drainOnce(row));
      }
    });
  }

  Future<void> onMetrics(List<RelayMetric> metrics) async {
    for (final m in metrics) {
      final objectId = m.objectId;
      if (objectId == null) continue;
      if (m.kind == 'ack') {
        await _markByObjectId(objectId, 'acked');
      } else if (m.kind == 'expired') {
        await _markByObjectId(objectId, 'expired');
      }
    }
  }

  Future<void> _markByObjectId(int objectId, String state) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(
      _db.outboxEvents,
    )..where((t) => t.objectId.equals(objectId))).write(
      OutboxEventsCompanion(state: Value(state), updatedAtMs: Value(now)),
    );
  }

  Future<void> _drainOnce(OutboxEvent row) async {
    try {
      final objectId = row.objectId;
      final payload = row.payload;
      if (objectId == null || payload == null) {
        await _db.markState(
          row.eventId,
          'failed',
          DateTime.now().millisecondsSinceEpoch,
        );
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      if (row.expiresAtMs <= now) {
        await _db.markState(row.eventId, 'expired', now);
        return;
      }
      await _db.markState(row.eventId, 'relaying', now);
      await _send(
        MeshEnvelope(
          objectId: objectId,
          eventId: row.eventId,
          siteId: row.siteId,
          roomId: row.roomId,
          createdAtMs: row.createdAtMs,
          expiresAtMs: row.expiresAtMs,
          hopCount: 0,
          hopLimit: 4,
          priority: _priorityFor(row.payloadType),
          payloadType: PayloadType.values.byName(row.payloadType),
          payload: Uint8List.fromList(payload),
          originEphemeralId: localEphemeralId,
        ),
      );
    } catch (_) {
      // Keep the row durable without creating a hot retry loop.
      final timer = Timer(const Duration(seconds: 1), () async {
        if (_disposed) return;
        final current = await (_db.select(
          _db.outboxEvents,
        )..where((t) => t.eventId.equals(row.eventId))).getSingleOrNull();
        if (current?.state == 'relaying') {
          await _db.markState(
            row.eventId,
            'ready',
            DateTime.now().millisecondsSinceEpoch,
          );
        }
      });
      _retryTimers[row.eventId]?.cancel();
      _retryTimers[row.eventId] = timer;
    } finally {
      _draining.remove(row.eventId);
    }
  }

  PriorityBand _priorityFor(String payloadType) =>
      switch (PayloadType.values.byName(payloadType)) {
        PayloadType.structuredSos => PriorityBand.p0Critical,
        PayloadType.responderUpdate => PriorityBand.p1High,
        PayloadType.voiceManifest ||
        PayloadType.voiceObject => PriorityBand.p2Normal,
        _ => PriorityBand.p2Normal,
      };

  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _draining.clear();
  }
}
