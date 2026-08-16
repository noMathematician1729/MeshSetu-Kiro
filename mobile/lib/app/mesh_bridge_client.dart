import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../core/data/database.dart';
import '../core/data/outbox_sender.dart';
import '../core/model/model.dart';
import '../feature/gateway/gateway_bridge.dart';
import '../feature/sos/sos_payload.dart';
import '../feature/voice/voice_repository.dart';
import 'mesh_bridge.dart';

/// UI-isolate half of the cross-isolate mesh bridge (see `mesh_bridge.dart`
/// for the wire format, `event_mode_screen.dart` for the background half).
/// Drains the Drift outbox by forwarding envelopes to the foreground task
/// and applies ACK/received notifications coming back from it. Only useful
/// once event mode is running — if the background isolate isn't up yet,
/// `sendDataToTask` is a no-op and rows simply wait in `relaying` until it
/// starts (matches how `feature/sos`/`feature/rooms` are meant to be used:
/// after "Start event mode").
class MeshBridgeClient {
  MeshBridgeClient(this._db);

  final MeshDatabase _db;
  OutboxSender? _outbox;
  bool _listening = false;
  GatewayBridge? _gatewayBridge;
  String? _siteId;
  int? _localEphemeralId;
  final Map<int, Completer<void>> _pendingSubmissions = {};
  final Map<int, Timer> _submissionTimers = {};

  /// Non-null only on the one phone acting as gateway (Bible §15.1);
  /// [feature/gateway/gateway_screen.dart] flips this on/off.
  set gatewayBridge(GatewayBridge? bridge) => _gatewayBridge = bridge;

  void start({required String siteId, required int localEphemeralId}) {
    if (!_listening) {
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
      _listening = true;
    }
    _siteId = siteId;
    _localEphemeralId = localEphemeralId;
    unawaited(_restartOutbox());
  }

  void setSiteId(String siteId) {
    if (_siteId == siteId || _localEphemeralId == null) return;
    _siteId = siteId;
    unawaited(_restartOutbox());
  }

  Future<void> _restartOutbox() async {
    await _outbox?.dispose();
    final siteId = _siteId;
    final localEphemeralId = _localEphemeralId;
    if (siteId == null || localEphemeralId == null) return;
    _outbox = OutboxSender(
      _db,
      _sendToMesh,
      siteId: siteId,
      localEphemeralId: localEphemeralId,
    )..start();
  }

  Future<void> _sendToMesh(MeshEnvelope envelope) async {
    if (!await FlutterForegroundTask.isRunningService) {
      throw StateError('event mode is not running');
    }
    final pending = Completer<void>();
    _pendingSubmissions[envelope.objectId] = pending;
    _submissionTimers[envelope.objectId] = Timer(
      const Duration(seconds: 10),
      () {
        if (!pending.isCompleted) {
          pending.completeError(
            StateError('foreground mesh did not accept the object'),
          );
        }
        _pendingSubmissions.remove(envelope.objectId);
        _submissionTimers.remove(envelope.objectId);
      },
    );
    FlutterForegroundTask.sendDataToTask({
      'sendMeshObject': MeshBridge.envelopeToJson(envelope),
      'objectId': envelope.objectId,
    });
    try {
      await pending.future;
    } finally {
      _submissionTimers.remove(envelope.objectId)?.cancel();
      _pendingSubmissions.remove(envelope.objectId);
    }
  }

  void _onTaskData(Object data) {
    if (data is! Map) return;
    switch (data['status']) {
      case 'mesh_submit_result':
        final objectId = data['objectId'];
        if (objectId is! int) return;
        final pending = _pendingSubmissions[objectId];
        if (pending == null || pending.isCompleted) return;
        if (data['accepted'] == true) {
          pending.complete();
        } else {
          pending.completeError(
            StateError(
              data['reason'] as String? ?? 'foreground mesh rejected object',
            ),
          );
        }
      case 'mesh_metric':
        final metrics = data['metrics'];
        if (metrics is! List) return;
        unawaited(
          _outbox?.onMetrics([
                for (final m in metrics)
                  if (m is Map)
                    MeshBridge.metricFromJson(m.cast<Object?, Object?>()),
              ]) ??
              Future.value(),
        );
      case 'mesh_received':
        final receivedJson = data['received'];
        if (receivedJson is! Map) return;
        final received = MeshBridge.receivedFromJson(
          receivedJson.cast<Object?, Object?>(),
        );
        unawaited(
          _db.insertInbox(
            InboxEventsCompanion.insert(
              objectId: Value(received.envelope.objectId),
              eventId: received.envelope.eventId,
              siteId: received.envelope.siteId,
              roomId: received.envelope.roomId,
              payloadType: received.envelope.payloadType.name,
              payload: received.envelope.payload,
              peerId: received.peerId,
              receivedAtMs: received.receivedAtMs,
            ),
          ),
        );
        final bridge = _gatewayBridge;
        if (bridge != null &&
            (received.envelope.payloadType == PayloadType.structuredSos ||
                received.envelope.payloadType == PayloadType.voiceObject)) {
          unawaited(_forwardToGateway(bridge, received));
        }
      case 'error' || 'stopped':
        _failPendingSubmissions(
          StateError(data['message'] as String? ?? 'foreground mesh stopped'),
        );
    }
  }

  void _failPendingSubmissions(Object error) {
    for (final pending in _pendingSubmissions.values) {
      if (!pending.isCompleted) pending.completeError(error);
    }
    for (final timer in _submissionTimers.values) {
      timer.cancel();
    }
    _pendingSubmissions.clear();
    _submissionTimers.clear();
  }

  Future<void> _forwardToGateway(
    GatewayBridge bridge,
    ReceivedObject received,
  ) async {
    try {
      switch (received.envelope.payloadType) {
        case PayloadType.structuredSos:
          final sos = StructuredSosPayload.decode(received.envelope.payload);
          await bridge.postToDashboard(
            bridge.eventJson(envelope: received.envelope, sos: sos),
          );
        case PayloadType.voiceObject:
          final voice = VoiceObjectPayload.decode(received.envelope.payload);
          await bridge.postToDashboard(bridge.voiceCompleteJson(voice));
        default:
          return;
      }
    } catch (_) {
      // Bible §3.4: gateway failure must not affect the local BLE loop.
    }
  }

  Future<void> dispose() async {
    if (_listening) {
      FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
      _listening = false;
    }
    await _outbox?.dispose();
    _outbox = null;
    _failPendingSubmissions(StateError('mesh bridge disposed'));
    _siteId = null;
    _localEphemeralId = null;
  }
}
