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
import '../feature/gateway/gateway_bridge.dart';
import '../feature/sos/sos_payload.dart';
import '../feature/voice/voice_repository.dart';
import 'debug_runtime_log.dart';
import 'mesh_bridge.dart';
import 'sos_alert_notifications.dart';
import 'sos_incident_navigator.dart';

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
    // #region agent log
    DebugRuntimeLog.write(
      hypothesisId: 'H3',
      location: 'mesh_bridge_client.dart:gatewayBridge',
      message: 'Gateway forwarding configuration applied',
      data: {'configured': bridge != null},
    );
    // #endregion
    if (bridge != null) unawaited(_syncRelayInbox());
  }

  void start({required String siteId, required int localEphemeralId}) {
    if (!_listening) {
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
      _listening = true;
    }
    _siteId = siteId;
    _localEphemeralId = localEphemeralId;
    // #region agent log
    DebugRuntimeLog.write(
      hypothesisId: 'H1',
      location: 'mesh_bridge_client.dart:start',
      message: 'Mesh bridge started',
      data: {'siteId': siteId, 'hasLocalEphemeralId': localEphemeralId != 0},
    );
    // #endregion
    unawaited(_restartOutbox());
    unawaited(_syncRelayInbox());
    _inboxSyncTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_syncRelayInbox()),
    );
  }

  void setSiteId(String siteId) {
    if (_siteId == siteId || _localEphemeralId == null) return;
    _siteId = siteId;
    unawaited(_restartOutbox());
    unawaited(_syncRelayInbox());
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
        // #region agent log
        DebugRuntimeLog.write(
          hypothesisId: 'H1',
          location: 'mesh_bridge_client.dart:mesh_submit_result',
          message: 'Foreground mesh submission result',
          data: {
            'objectId': objectId,
            'accepted': data['accepted'] == true,
            'reason': data['reason']?.toString(),
          },
        );
        // #endregion
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
        final transportMetrics = metrics
            .whereType<Map>()
            .map((metric) => Map<String, Object?>.from(metric))
            .where(
              (metric) => const {
                'scheduler_selected_peer',
                'frames_sent',
                'ack',
                'send_failed',
                'deferred_mtu',
                'gatt_connection_failed',
              }.contains(metric['kind']),
            )
            .map(
              (metric) => {
                'kind': metric['kind'],
                'objectId': metric['objectId'],
                'peerId': metric['peerId'],
                'detail': metric['detail'],
                'value': metric['value'],
              },
            )
            .toList();
        if (transportMetrics.isNotEmpty) {
          // #region agent log
          DebugRuntimeLog.write(
            hypothesisId: 'H1',
            location: 'mesh_bridge_client.dart:mesh_metric',
            message: 'GATT transport metrics reached UI bridge',
            data: {'metrics': transportMetrics},
          );
          // #endregion
        }
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
        unawaited(_storeReceived(received));
      case 'mesh_origin_submitted':
        final envelopeJson = data['envelope'];
        final encryptedBytes = data['encryptedBytes'];
        if (envelopeJson is! Map ||
            encryptedBytes is! String ||
            _gatewayBridge == null) {
          // #region agent log
          DebugRuntimeLog.write(
            hypothesisId: 'H3',
            location: 'mesh_bridge_client.dart:mesh_origin_submitted',
            message: 'Origin object was not eligible for gateway forwarding',
            data: {
              'hasEnvelope': envelopeJson is Map,
              'hasEncryptedBytes': encryptedBytes is String,
              'gatewayConfigured': _gatewayBridge != null,
            },
          );
          // #endregion
          return;
        }
        unawaited(
          _forwardOriginSos(
            MeshBridge.envelopeFromJson(envelopeJson.cast<Object?, Object?>()),
            base64Decode(encryptedBytes),
          ),
        );
      case 'error' || 'stopped':
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
    // #region agent log
    DebugRuntimeLog.write(
      hypothesisId: 'H3',
      location: 'mesh_bridge_client.dart:_forwardOriginSos',
      message: 'Starting origin encrypted-object gateway upload',
      data: {
        'objectId': envelope.objectId,
        'payloadType': envelope.payloadType.name,
        'packetBytes': encryptedBytes.length,
      },
    );
    // #endregion
    try {
      await bridge.postEncryptedObject(
        siteId: envelope.siteId,
        objectId: envelope.objectId,
        packet: encryptedBytes,
        receivedAtMs: DateTime.now().millisecondsSinceEpoch,
        peerId: 'origin',
      );
      // #region agent log
      DebugRuntimeLog.write(
        hypothesisId: 'H3',
        location: 'mesh_bridge_client.dart:_forwardOriginSos',
        message: 'Origin encrypted-object gateway upload succeeded',
        data: {'objectId': envelope.objectId},
      );
      // #endregion
    } catch (error) {
      // #region agent log
      DebugRuntimeLog.write(
        hypothesisId: 'H3',
        location: 'mesh_bridge_client.dart:_forwardOriginSos',
        message: 'Origin encrypted-object gateway upload failed',
        data: {'objectId': envelope.objectId, 'error': '$error'},
      );
      // #endregion
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

  /// Forwards a received CEAL-style compact SOS alert to the admin backend
  /// for UID→profile resolution. Every phone with connectivity acts as a
  /// beacon/gateway for UID-only alerts, matching CEAL's architecture.
  Future<void> _forwardCompactSos(Map data) async {
    final bridge = _gatewayBridge ?? _fallbackBridge();
    if (bridge == null) return;
    final dedupeKey = data['dedupeKey'] as String?;
    if (dedupeKey == null || !_forwardedCompactAlerts.add(dedupeKey)) return;
    final originId = data['originId'] as int?;
    final sequence = data['sequence'] as int?;
    // Derive the reporterUid hex from originId (reverse of the 4-byte
    // truncation used when broadcasting). Pad to 12 chars with trailing zeros
    // to match the full UID length stored in the profiles table.
    final reporterUid = originId != null
        ? originId.toRadixString(16).padLeft(8, '0').padRight(12, '0')
        : '';
    if (reporterUid.isEmpty) return;
    try {
      final (success, _) = await bridge.forwardCealSos(
        reporterUid: reporterUid,
        siteId: _siteId ?? 'demo-site',
        originId: originId,
        sequence: sequence,
      );
      // #region agent log
      DebugRuntimeLog.write(
        hypothesisId: 'H3',
        location: 'mesh_bridge_client.dart:_forwardCompactSos',
        message: 'Compact SOS gateway upload completed',
        data: {'success': success, 'originIdPresent': originId != null},
      );
      // #endregion
      if (!success) _forwardedCompactAlerts.remove(dedupeKey);
    } catch (error) {
      // #region agent log
      DebugRuntimeLog.write(
        hypothesisId: 'H3',
        location: 'mesh_bridge_client.dart:_forwardCompactSos',
        message: 'Compact SOS gateway upload failed',
        data: {'error': '$error'},
      );
      // #endregion
      // Best-effort: if connectivity is unavailable, the alert was still
      // shown locally and may be forwarded by another peer with Wi-Fi.
      _forwardedCompactAlerts.remove(dedupeKey);
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
      if (!await directory.exists()) return;
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
    } finally {
      _syncingInbox = false;
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
      // #region agent log
      DebugRuntimeLog.write(
        hypothesisId: 'H3',
        location: 'mesh_bridge_client.dart:_storeReceived',
        message: 'Received rich object not forwarded to gateway',
        data: {
          'objectId': objectId,
          'gatewayConfigured': bridge != null,
          'payloadType': received.envelope.payloadType.name,
          'alreadyForwarded': _forwardedObjectIds.contains(objectId),
        },
      );
      // #endregion
      return;
    }
    try {
      await _forwardToGateway(bridge, received);
      _forwardedObjectIds.add(objectId);
      // #region agent log
      DebugRuntimeLog.write(
        hypothesisId: 'H3',
        location: 'mesh_bridge_client.dart:_storeReceived',
        message: 'Received rich object gateway upload succeeded',
        data: {'objectId': objectId},
      );
      // #endregion
    } catch (error) {
      // #region agent log
      DebugRuntimeLog.write(
        hypothesisId: 'H3',
        location: 'mesh_bridge_client.dart:_storeReceived',
        message: 'Received rich object gateway upload failed',
        data: {'objectId': objectId, 'error': '$error'},
      );
      // #endregion
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
      FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
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
  }
}
