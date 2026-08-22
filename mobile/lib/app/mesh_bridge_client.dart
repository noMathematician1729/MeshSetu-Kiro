import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';

import '../core/data/database.dart';
import '../core/data/outbox_sender.dart';
import '../core/model/model.dart';
import '../core/protocol/envelope_codec.dart';
import '../core/protocol/relay_engine.dart';
import '../feature/gateway/gateway_bridge.dart';
import '../feature/sos/sos_payload.dart';
import '../feature/voice/voice_repository.dart';
import 'mesh_bridge.dart';
import 'sos_alert_notifications.dart';
import 'sos_incident_navigator.dart';

/// Snapshot of the foreground mesh service's connectivity, observable from
/// the UI isolate without polling. Room screens use this as the primary
/// delivery signal instead of the internet-only [RoomPresenceSocket] status
/// — a healthy BLE mesh with zero internet should never look like a broken
/// connection.
class MeshStatus {
  const MeshStatus({
    required this.eventModeRunning,
    required this.peerCount,
    required this.statusText,
    this.blockedReason,
    this.siteMismatchDetected = false,
  });

  static const stopped = MeshStatus(
    eventModeRunning: false,
    peerCount: 0,
    statusText: 'stopped',
  );

  final bool eventModeRunning;
  final int peerCount;
  final String statusText;

  /// Human-readable reason the radio could not start at all (Bible audit
  /// Task 7) — e.g. Bluetooth off, a missing permission, or Android's
  /// Location toggle. Non-null only while [eventModeRunning] is false and
  /// the most recent [EventModeLauncher.start] attempt was blocked by
  /// [MeshRadioPreflight]. Distinguishes "the radio itself cannot run"
  /// from "it is running but has found nobody yet".
  final String? blockedReason;

  /// True once this scan cycle's `scan_fingerprint_mismatches` metric was
  /// nonzero — a nearby device is advertising the MeshSetu service but for
  /// a different site/event (Bible audit Task 7/A4). This is reset to
  /// false whenever a cycle reports zero mismatches, so it reflects
  /// current, not historical, conditions.
  final bool siteMismatchDetected;

  MeshStatus copyWith({
    bool? eventModeRunning,
    int? peerCount,
    String? statusText,
    String? blockedReason,
    bool clearBlockedReason = false,
    bool? siteMismatchDetected,
  }) => MeshStatus(
    eventModeRunning: eventModeRunning ?? this.eventModeRunning,
    peerCount: peerCount ?? this.peerCount,
    statusText: statusText ?? this.statusText,
    blockedReason: clearBlockedReason
        ? null
        : (blockedReason ?? this.blockedReason),
    siteMismatchDetected: siteMismatchDetected ?? this.siteMismatchDetected,
  );
}

/// UI-isolate half of the cross-isolate mesh bridge (see `mesh_bridge.dart`
/// for the wire format, `event_mode_screen.dart` for the background half).
/// Drains the Drift outbox by forwarding envelopes to the foreground task
/// and applies ACK/received notifications coming back from it. Only useful
/// once event mode is running — if the background isolate isn't up yet,
/// `sendDataToTask` is a no-op and rows simply wait in `relaying` until it
/// starts (matches how `feature/sos`/`feature/rooms` are meant to be used:
/// after "Start event mode").
class MeshBridgeClient {
  MeshBridgeClient(
    this._db, {
    Future<void> Function(MeshEnvelope envelope)? sendToMesh,
    this.onOriginForward,
    this.registerTaskDataCallback = true,
    this.syncRelayInbox = true,
  }) : _sendToMeshOverride = sendToMesh;

  final MeshDatabase _db;
  final Future<void> Function(MeshEnvelope envelope)? _sendToMeshOverride;
  void Function(MeshEnvelope envelope, Object? error)? onOriginForward;
  final bool registerTaskDataCallback;
  final bool syncRelayInbox;
  OutboxSender? _outbox;
  bool _listening = false;
  GatewayBridge? _gatewayBridge;
  String? _siteId;
  int? _localEphemeralId;
  final Map<int, Completer<void>> _pendingSubmissions = {};
  final Map<int, Timer> _submissionTimers = {};
  final Set<int> _storedObjectIds = {};
  final Set<int> _forwardedObjectIds = {};
  final Set<int> _forwardingObjectIds = {};
  Timer? _inboxSyncTimer;
  bool _syncingInbox = false;
  String? _reporterUid;
  GatewayBridge? _contactBridge;
  Timer? _contactNotificationTimer;
  bool _pollingContactNotifications = false;
  bool _contactNotificationsPrimed = false;
  final Set<String> _deliveredContactNotifications = {};
  final _meshStatusController = StreamController<MeshStatus>.broadcast();
  MeshStatus _meshStatus = MeshStatus.stopped;

  /// Current mesh connectivity snapshot; [meshStatusStream] emits every
  /// change. Safe to read before [start] — defaults to [MeshStatus.stopped].
  MeshStatus get meshStatus => _meshStatus;
  Stream<MeshStatus> get meshStatusStream => _meshStatusController.stream;

  /// Records why the radio failed to start at all (Bible audit Task 7).
  /// Called by [EventModeLauncher]/[RoomMeshBootstrap] when
  /// [MeshRadioPreflight] blocks startup before the foreground task ever
  /// runs, since no `mesh_metric`/`mesh_status` callback will otherwise
  /// arrive to explain why `eventModeRunning` stayed false.
  void reportBlockedReason(String reason) {
    _updateMeshStatus((current) => current.copyWith(blockedReason: reason));
  }

  void _updateMeshStatus(MeshStatus Function(MeshStatus current) update) {
    final next = update(_meshStatus);
    _meshStatus = next;
    if (!_meshStatusController.isClosed) _meshStatusController.add(next);
  }

  /// Enables emergency-contact alert delivery for the signed-in profile.
  void configureContactAlerts({
    required String? reporterUid,
    required GatewayBridge? bridge,
  }) {
    _reporterUid = reporterUid;
    _contactBridge = bridge;
    if (reporterUid == null || reporterUid.isEmpty || bridge == null) {
      _contactNotificationTimer?.cancel();
      _contactNotificationTimer = null;
      return;
    }
    unawaited(_pollContactNotifications());
    _contactNotificationTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_pollContactNotifications()),
    );
  }

  /// Non-null only on the one phone acting as gateway (Bible §15.1);
  /// [feature/gateway/gateway_screen.dart] flips this on/off.
  GatewayBridge? get gatewayBridge => _gatewayBridge;
  set gatewayBridge(GatewayBridge? bridge) {
    _gatewayBridge = bridge;
    if (bridge != null) unawaited(_syncRelayInbox());
  }

  void start({required String siteId, required int localEphemeralId}) {
    _ensureTaskDataListener();
    _siteId = siteId;
    _localEphemeralId = localEphemeralId;
    _activateOutbox();
  }

  /// Attaches this client to a site before the foreground task has reported
  /// its local identity. Room screens use this when they start Event Mode
  /// directly; the outbox begins draining as soon as `started` arrives.
  void prepareForSite({required String siteId}) {
    _ensureTaskDataListener();
    final changed = _siteId != siteId;
    _siteId = siteId;
    if (changed && _localEphemeralId != null) _activateOutbox();
  }

  /// Requests the identity from an already-running foreground task. This is
  /// needed when a participant opens a room after Event Mode was started by a
  /// different screen, so the room-created bridge can attach without a task
  /// restart.
  void requestForegroundIdentity() {
    if (_siteId == null) return;
    FlutterForegroundTask.sendDataToTask(const {'mesh_identity_request': true});
  }

  void _ensureTaskDataListener() {
    if (_listening || !registerTaskDataCallback) return;
    FlutterForegroundTask.addTaskDataCallback(handleTaskData);
    _listening = true;
  }

  void _acceptForegroundIdentity(int localEphemeralId) {
    if (localEphemeralId <= 0 || _localEphemeralId == localEphemeralId) {
      return;
    }
    _localEphemeralId = localEphemeralId;
    if (_siteId != null) _activateOutbox();
  }

  void _activateOutbox() {
    unawaited(_restartOutbox());
    if (!syncRelayInbox) return;
    unawaited(_syncRelayInbox());
    _inboxSyncTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_syncRelayInbox()),
    );
  }

  void setSiteId(String siteId) {
    prepareForSite(siteId: siteId);
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
    final override = _sendToMeshOverride;
    if (override != null) {
      await override(envelope);
      return;
    }
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

  /// Consumes a foreground-task message. Public so its status projection can
  /// be unit-tested without a real Android foreground service; production
  /// registers this exact method as the task-data callback in [start].
  void handleTaskData(Object data) {
    if (data is! Map) return;
    switch (data['status']) {
      case 'started':
        final localEphemeralId = data['localEphemeralId'];
        if (localEphemeralId is int) {
          _acceptForegroundIdentity(localEphemeralId);
        }
        _updateMeshStatus(
          (current) => current.copyWith(
            eventModeRunning: true,
            clearBlockedReason: true,
          ),
        );
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
      case 'mesh_status':
        final value = data['value'];
        if (value is! String) return;
        _updateMeshStatus(
          (current) =>
              current.copyWith(eventModeRunning: true, statusText: value),
        );
      case 'mesh_peers':
        final peers = data['peers'];
        if (peers is! List) return;
        _updateMeshStatus(
          (current) => current.copyWith(
            eventModeRunning: true,
            peerCount: peers.whereType<Map>().where((peer) {
              final connected = peer['connected'];
              return connected == null || connected == true;
            }).length,
          ),
        );
      case 'mesh_metric':
        final metrics = data['metrics'];
        if (metrics is! List) return;
        final decoded = [
          for (final m in metrics)
            if (m is Map) MeshBridge.metricFromJson(m.cast<Object?, Object?>()),
        ];
        for (final metric in decoded) {
          if (metric.kind == 'scan_fingerprint_mismatches') {
            _updateMeshStatus(
              (current) => current.copyWith(
                siteMismatchDetected: (metric.value ?? 0) > 0,
              ),
            );
          }
        }
        unawaited(_outbox?.onMetrics(decoded) ?? Future.value());
      case 'mesh_received':
        final receivedJson = data['received'];
        if (receivedJson is! Map) return;
        final received = MeshBridge.receivedFromJson(
          receivedJson.cast<Object?, Object?>(),
        );
        unawaited(_storeReceived(received));
      case 'mesh_origin_submitted':
        final envelopeJson = data['envelope'];
        final encryptedBytes = data['encryptedBytes'];
        if (envelopeJson is! Map ||
            encryptedBytes is! String ||
            _gatewayBridge == null) {
          return;
        }
        unawaited(
          _forwardOriginSos(
            MeshBridge.envelopeFromJson(envelopeJson.cast<Object?, Object?>()),
            base64Decode(encryptedBytes),
          ),
        );
      case 'error' || 'stopped':
        _updateMeshStatus((_) => MeshStatus.stopped);
        _failPendingSubmissions(
          StateError(data['message'] as String? ?? 'foreground mesh stopped'),
        );
    }
  }

  Future<void> _forwardOriginSos(
    MeshEnvelope envelope,
    List<int> encryptedBytes,
  ) async {
    final bridge = _gatewayBridge;
    if (bridge == null ||
        (envelope.payloadType != PayloadType.structuredSos &&
            envelope.payloadType != PayloadType.voiceObject)) {
      return;
    }
    try {
      await bridge.postEncryptedObject(
        siteId: envelope.siteId,
        objectId: envelope.objectId,
        packet: encryptedBytes,
        receivedAtMs: DateTime.now().millisecondsSinceEpoch,
        peerId: 'origin',
      );
      onOriginForward?.call(envelope, null);
    } catch (error) {
      onOriginForward?.call(envelope, error);
      // Relay delivery can still carry this object to another gateway.
    }
  }

  /// Delivers alerts the backend addressed to this account because the sender
  /// listed it as an emergency contact. Polling keeps the app free of a
  /// third-party push dependency; the server-side delivery record is the
  /// contract, so FCM can replace this without changing the backend.
  Future<void> _pollContactNotifications() async {
    final uid = _reporterUid;
    final bridge = _contactBridge;
    if (uid == null || uid.isEmpty || bridge == null) return;
    if (_pollingContactNotifications) return;
    _pollingContactNotifications = true;
    try {
      final records = await bridge.fetchNotifications(uid);
      // First pass after launch only primes the seen-set so a contact is not
      // alerted for a backlog of historical incidents.
      final priming = !_contactNotificationsPrimed;
      _contactNotificationsPrimed = true;
      for (final record in records.reversed) {
        final id = '${record['notification_id'] ?? ''}';
        if (id.isEmpty || !_deliveredContactNotifications.add(id)) continue;
        if (priming) continue;
        final eventId = '${record['event_id'] ?? ''}';
        await SosAlertNotifications.show(
          id: SosAlertNotifications.idForKey('contact:$id'),
          title: '${record['title'] ?? 'Emergency alert'}',
          body:
              '${record['body'] ?? 'An emergency contact needs help.'}'
              '\nTap to open the full incident page.',
          payload: eventId.isEmpty
              ? null
              : SosIncidentNavigator.payloadForEvent(eventId),
        );
      }
    } catch (_) {
      // Connectivity failures retry on the next poll tick.
    } finally {
      _pollingContactNotifications = false;
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

  /// Imports the foreground relay's durable inbox. Live task callbacks remain
  /// the fast path, but Android can suspend the UI isolate and drop those
  /// callbacks while the foreground BLE isolate keeps receiving. The relay
  /// writes each decrypted/authenticated envelope atomically before ACKing,
  /// so replaying these files makes delivery into Drift lossless.
  Future<void> _syncRelayInbox() async {
    if (_syncingInbox || _siteId == null) return;
    _syncingInbox = true;
    try {
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory('${documents.path}/mesh-relay/inbox');
      if (await directory.exists()) {
        await for (final entity in directory.list()) {
          if (entity is! File || !entity.path.endsWith('.bin')) continue;
          try {
            final envelope = EnvelopeCodec.decode(await entity.readAsBytes());
            if (envelope.siteId != _siteId ||
                envelope.expiresAtMs <= DateTime.now().millisecondsSinceEpoch) {
              continue;
            }
            final modifiedAt =
                (await entity.stat()).modified.millisecondsSinceEpoch;
            final wire = File(
              '${directory.path}/${entity.uri.pathSegments.last.replaceFirst('.bin', '.wire')}',
            );
            await _storeReceived(
              ReceivedObject(
                envelope: envelope,
                peerId: 'durable-relay',
                receivedAtMs: modifiedAt,
                encryptedBytes: await wire.exists()
                    ? await wire.readAsBytes()
                    : null,
              ),
            );
          } catch (_) {
            // Ignore incomplete/foreign files; atomic writes mean valid packets
            // will be available on the next pass.
          }
        }
      }
      await _syncRelayAcknowledgements(documents);
    } finally {
      _syncingInbox = false;
    }
  }

  /// The foreground isolate can receive an ACK while the UI isolate is
  /// paused, so the task writes a tiny durable marker beside its relay store.
  /// Consume it here instead of relying solely on the best-effort task-data
  /// callback.
  Future<void> _syncRelayAcknowledgements(Directory documents) async {
    final outbox = _outbox;
    if (outbox == null) return;
    final directory = Directory('${documents.path}/mesh-relay/acks');
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.ack')) continue;
      try {
        final payload = jsonDecode(await entity.readAsString());
        final objectId = payload is Map
            ? int.tryParse('${payload['objectId'] ?? ''}')
            : null;
        if (objectId == null || objectId <= 0) {
          await entity.delete();
          continue;
        }
        final peerId = payload is Map ? payload['peerId'] as String? : null;
        await outbox.onMetrics([
          RelayMetric('ack', objectId: objectId, peerId: peerId),
        ]);
        await entity.delete();
      } catch (_) {
        // Atomic marker writes are retried on the next sync pass.
      }
    }
  }

  Future<void> _storeReceived(ReceivedObject received) async {
    final objectId = received.envelope.objectId;
    if (_storedObjectIds.add(objectId)) {
      try {
        await _db.insertInbox(
          InboxEventsCompanion.insert(
            objectId: Value(objectId),
            eventId: received.envelope.eventId,
            siteId: received.envelope.siteId,
            roomId: received.envelope.roomId,
            payloadType: received.envelope.payloadType.name,
            payload: received.envelope.payload,
            peerId: received.peerId,
            receivedAtMs: received.receivedAtMs,
          ),
        );
      } catch (_) {
        _storedObjectIds.remove(objectId);
        rethrow;
      }
    }
    final bridge = _gatewayBridge;
    if (bridge == null ||
        (received.envelope.payloadType != PayloadType.structuredSos &&
            received.envelope.payloadType != PayloadType.voiceObject) ||
        _forwardedObjectIds.contains(objectId) ||
        !_forwardingObjectIds.add(objectId)) {
      return;
    }
    try {
      await _forwardToGateway(bridge, received);
      _forwardedObjectIds.add(objectId);
    } catch (_) {
      // Keep the object eligible for the next durable-inbox retry.
    } finally {
      _forwardingObjectIds.remove(objectId);
    }
  }

  Future<void> _forwardToGateway(
    GatewayBridge bridge,
    ReceivedObject received,
  ) async {
    final wire = received.encryptedBytes;
    if (wire != null &&
        (received.envelope.payloadType == PayloadType.structuredSos ||
            received.envelope.payloadType == PayloadType.voiceObject)) {
      await bridge.postEncryptedObject(
        siteId: received.envelope.siteId,
        objectId: received.envelope.objectId,
        packet: wire,
        receivedAtMs: received.receivedAtMs,
        peerId: received.peerId,
      );
      return;
    }
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
  }

  Future<void> dispose() async {
    _inboxSyncTimer?.cancel();
    _inboxSyncTimer = null;
    _contactNotificationTimer?.cancel();
    _contactNotificationTimer = null;
    if (_listening) {
      FlutterForegroundTask.removeTaskDataCallback(handleTaskData);
      _listening = false;
    }
    await _outbox?.dispose();
    _outbox = null;
    _failPendingSubmissions(StateError('mesh bridge disposed'));
    _siteId = null;
    _localEphemeralId = null;
    _storedObjectIds.clear();
    _forwardedObjectIds.clear();
    _forwardingObjectIds.clear();
    _meshStatus = MeshStatus.stopped;
    await _meshStatusController.close();
  }
}
