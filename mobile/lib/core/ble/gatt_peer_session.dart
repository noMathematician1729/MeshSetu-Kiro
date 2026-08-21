import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'async_lock.dart';
import 'mesh_gatt.dart';

/// A diagnostic event from one client-role GATT session.
///
/// The native plugin completes each awaited operation from its Android GATT
/// callback. Keeping this callback at the session boundary makes the
/// connection phase visible without leaking platform-specific objects into
/// the transport scheduler.
typedef GattLifecycleListener =
    void Function(String kind, {String? phase, String? detail, int? value});

/// The transport only becomes usable at [ready]. Discovery and connection are
/// deliberately separate states: an advertisement or a bare GATT connection
/// is not a MeshSetu peer session.
enum PeerSessionState {
  connecting,
  connected,
  negotiating,
  discoveringServices,
  validatingAttributes,
  subscribingNotifications,
  ready,
  disconnected,
  failed,
}

/// Port of `in.meshsetu.ble.GattPeerSession` (Kotlin `GattPeerSession.kt`).
///
/// `universal_ble` exposes Android's callback completions as futures. The
/// session still owns an explicit per-device operation lock so setup and frame
/// writes cannot overlap even if the plugin queue is changed to `none` by a
/// caller. Each operation also has its own timeout and phase.
class GattPeerSession {
  GattPeerSession._(this.deviceId, this._onLifecycle, this._mtuTimeout)
    : _queueId = 'mesh-gatt-${deviceId.toLowerCase()}' {
    _incomingController = StreamController<Uint8List>(
      onListen: () => _incomingStreamWasListened = true,
    );
    // Subscribe before connect/setup. The server can send HELLO, ACK, or a
    // queued object as soon as the CCCD write reaches it; a broadcast stream
    // created only at attach time would drop that first notification.
    _incomingSubscription =
        UniversalBle.characteristicValueStream(deviceId, MeshGatt.tx).listen((
          bytes,
        ) {
          _emit('client_tx_notification_received', value: bytes.length);
          _incomingController.add(bytes);
        });
  }

  static const _connectTimeout = Duration(seconds: 15);
  static const _defaultMtuTimeout = Duration(seconds: 5);
  static const _discoveryTimeout = Duration(seconds: 8);
  static const _subscriptionTimeout = Duration(seconds: 8);
  static const _writeTimeout = Duration(seconds: 5);

  final String deviceId;
  final GattLifecycleListener? _onLifecycle;
  final Duration _mtuTimeout;
  final String _queueId;
  int mtu = 23;

  PeerSessionState _state = PeerSessionState.connecting;
  PeerSessionState get state => _state;
  String _phase = 'connecting';
  Object? _failure;
  String get phase => _phase;
  String? get failure => _failure?.toString();

  final StreamController<PeerSessionState> _stateController =
      StreamController<PeerSessionState>.broadcast();
  Stream<PeerSessionState> get stateStream => _stateController.stream;

  late final StreamController<Uint8List> _incomingController;
  bool _incomingStreamWasListened = false;
  Stream<Uint8List> get incoming => _incomingController.stream;

  final Completer<void> _ready = Completer<void>();
  final AsyncLock _gattOperationLock = AsyncLock();
  final AsyncLock _writeLock = AsyncLock();
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<Uint8List>? _incomingSubscription;
  bool _closed = false;
  Future<void>? _closeFuture;

  static GattPeerSession open(
    String deviceId, {
    GattLifecycleListener? onLifecycle,
    Duration mtuTimeout = _defaultMtuTimeout,
  }) {
    final session = GattPeerSession._(deviceId, onLifecycle, mtuTimeout);
    unawaited(session._connect());
    return session;
  }

  Future<void> _connect() async {
    try {
      _setPhase('connect', PeerSessionState.connecting);
      _emit('connect_initiated');
      _connectionSubscription = UniversalBle.connectionStream(deviceId).listen((
        connected,
      ) {
        if (!connected && !_closed) {
          _failure = StateError('GATT disconnected during $_phase');
          _closed = true;
          _emit('gatt_disconnected', detail: _failure.toString());
          _markDisconnected();
        }
      });

      await _runOperation(
        'connect',
        () => UniversalBle.connect(deviceId, timeout: _connectTimeout),
        timeout: _connectTimeout,
      );
      _throwIfClosed();
      _setPhase('connected', PeerSessionState.connected);
      _emit('gatt_connected');

      _setPhase('request_mtu', PeerSessionState.negotiating);
      _emit('mtu_requested', value: 517);
      try {
        final negotiated = await _runOperation(
          'request_mtu',
          () => UniversalBle.requestMtu(
            deviceId,
            517,
            timeout: _mtuTimeout,
            queueId: _queueId,
          ),
          timeout: _mtuTimeout,
        );
        mtu = negotiated >= 23 ? negotiated : 23;
        _emit('mtu_changed', value: mtu, detail: 'effective_mtu=$mtu');
      } catch (error) {
        // A missing MTU callback means the native request may still be active.
        // Do not launch service discovery on top of it; fail this session and
        // let the coordinator close/reconnect it cleanly. A normal Android
        // status failure is safe to fall back from because its future has
        // already completed and been removed by the plugin.
        if (error is TimeoutException) rethrow;
        // Android is allowed to reject a larger MTU. This is not a transport
        // failure; the ATT default remains valid for fragmentation.
        mtu = 23;
        _emit(
          'mtu_failed',
          value: mtu,
          detail: '$error; using effective_mtu=23',
        );
      }
      _throwIfClosed();

      _setPhase('discover_services', PeerSessionState.discoveringServices);
      _emit('service_discovery_started');
      final services = await _runOperation(
        'discover_services',
        () => UniversalBle.discoverServices(
          deviceId,
          withDescriptors: true,
          timeout: _discoveryTimeout,
          queueId: _queueId,
        ),
        timeout: _discoveryTimeout,
      );
      _emit('services_discovered', value: services.length);
      _throwIfClosed();

      _setPhase('validate_attributes', PeerSessionState.validatingAttributes);
      _validateAttributes(services);

      _setPhase(
        'subscribe_notifications',
        PeerSessionState.subscribingNotifications,
      );
      _emit('notification_local_enable_requested');
      _emit('cccd_write_started');
      await _runOperation(
        'write_cccd',
        () => UniversalBle.subscribeNotifications(
          deviceId,
          MeshGatt.service,
          MeshGatt.tx,
          timeout: _subscriptionTimeout,
          queueId: _queueId,
        ),
        timeout: _subscriptionTimeout,
      );
      // The plugin returns only after setCharacteristicNotification and the
      // CCCD write callback both succeed.
      _emit('notification_local_enabled');
      _emit('cccd_write_complete', value: 0);
      _throwIfClosed();

      _setPhase('ready', PeerSessionState.ready);
      _emit('peer_session_ready', value: mtu);
      _ready.complete();
    } catch (error) {
      _failure ??= error;
      if (!_closed) {
        _emit('gatt_setup_failed', detail: '$_phase: $error');
        _setState(PeerSessionState.failed);
      }
      if (!_ready.isCompleted) _ready.completeError(error);
    }
  }

  Future<void> awaitReady() => _ready.future;

  Future<void> send(Uint8List bytes, {bool withResponse = true}) async {
    await _writeLock.synchronized(() async {
      await awaitReady();
      _emit('frame_write_started', value: bytes.length, detail: 'rx');
      try {
        await _runOperation(
          'write_rx',
          () => UniversalBle.write(
            deviceId,
            MeshGatt.service,
            MeshGatt.rx,
            bytes,
            withoutResponse: !withResponse,
            timeout: _writeTimeout,
            queueId: _queueId,
          ),
          timeout: _writeTimeout,
        );
        _emit('frame_write_api_result', value: 0, detail: 'accepted_locally');
      } catch (error) {
        _emit('frame_write_api_result', detail: 'failed: $error');
        rethrow;
      }
    });
  }

  Future<void> close() => _closeFuture ??= _dispose();

  Future<void> _dispose() async {
    _closed = true;
    _markDisconnected();
    try {
      await UniversalBle.disconnect(
        deviceId,
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {
      // The connection may already have failed; local state is still closed.
    } finally {
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      await _incomingSubscription?.cancel();
      _incomingSubscription = null;
      // A single-subscription controller can keep close() pending forever
      // when setup failed before any consumer attached to `incoming`.
      if (!_incomingStreamWasListened) {
        await _incomingController.stream.listen((_) {}).cancel();
      }
      await _incomingController.close();
      await _stateController.close();
    }
  }

  Future<T> _runOperation<T>(
    String operation,
    Future<T> Function() action, {
    required Duration timeout,
  }) {
    _emit('gatt_operation_queued', detail: operation);
    return _gattOperationLock.synchronized(() async {
      _throwIfClosed();
      _emit('gatt_operation_started', detail: operation);
      try {
        final result = await action().timeout(timeout);
        _emit('gatt_operation_completed', detail: operation);
        return result;
      } catch (error) {
        _emit('gatt_operation_failed', detail: '$operation: $error');
        if (error is TimeoutException && !_closed) {
          _failure ??= StateError('$operation timed out');
          _emit('gatt_operation_timeout', detail: operation);
          _setState(PeerSessionState.failed);
        }
        rethrow;
      }
    });
  }

  void _validateAttributes(List<BleService> services) {
    BleService? meshService;
    for (final service in services) {
      if (service.uuid.toLowerCase() == MeshGatt.service) {
        meshService = service;
        break;
      }
    }
    if (meshService == null) {
      throw StateError('mesh_service_missing');
    }
    _emit('mesh_service_found');

    BleCharacteristic? rx;
    BleCharacteristic? tx;
    for (final characteristic in meshService.characteristics) {
      if (characteristic.uuid.toLowerCase() == MeshGatt.rx) rx = characteristic;
      if (characteristic.uuid.toLowerCase() == MeshGatt.tx) tx = characteristic;
    }
    if (rx == null) throw StateError('rx_characteristic_missing');
    final rxProperties = _propertiesHex(rx.properties);
    _emit('rx_characteristic_found', detail: 'properties=$rxProperties');
    if (!rx.properties.contains(CharacteristicProperty.write) &&
        !rx.properties.contains(CharacteristicProperty.writeWithoutResponse)) {
      throw StateError('rx_not_writable:$rxProperties');
    }
    if (tx == null) throw StateError('tx_characteristic_missing');
    final txProperties = _propertiesHex(tx.properties);
    _emit('tx_characteristic_found', detail: 'properties=$txProperties');
    if (!tx.properties.contains(CharacteristicProperty.notify)) {
      throw StateError('tx_not_notifiable:$txProperties');
    }
    final hasCccd = tx.descriptors.any(
      (descriptor) => descriptor.uuid.toLowerCase() == MeshGatt.cccd,
    );
    if (!hasCccd) throw StateError('cccd_missing');
    _emit('cccd_found', detail: MeshGatt.cccd);
  }

  static String _propertiesHex(List<CharacteristicProperty> properties) {
    var bits = 0;
    for (final property in properties) {
      bits |= switch (property) {
        CharacteristicProperty.broadcast => 0x01,
        CharacteristicProperty.read => 0x02,
        CharacteristicProperty.writeWithoutResponse => 0x04,
        CharacteristicProperty.write => 0x08,
        CharacteristicProperty.notify => 0x10,
        CharacteristicProperty.indicate => 0x20,
        CharacteristicProperty.authenticatedSignedWrites => 0x40,
        CharacteristicProperty.extendedProperties => 0x80,
      };
    }
    return '0x${bits.toRadixString(16)}';
  }

  void _markDisconnected() {
    if (_state == PeerSessionState.disconnected) return;
    _setState(PeerSessionState.disconnected);
    if (!_ready.isCompleted) {
      _ready.completeError(StateError('GATT disconnected'));
    }
  }

  void _throwIfClosed() {
    if (_closed) throw StateError('GATT session closed');
  }

  void _setPhase(String phase, PeerSessionState state) {
    _phase = phase;
    _setState(state);
  }

  void _setState(PeerSessionState value) {
    _state = value;
    if (!_stateController.isClosed) _stateController.add(value);
  }

  void _emit(String kind, {String? detail, int? value}) {
    try {
      _onLifecycle?.call(kind, phase: _phase, detail: detail, value: value);
    } catch (_) {
      // Diagnostics must never change the BLE state machine's outcome.
    }
  }
}
