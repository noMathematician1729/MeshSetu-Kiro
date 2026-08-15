import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'async_lock.dart';
import 'mesh_gatt.dart';

/// Port of `in.meshsetu.ble.GattPeerSession` (Kotlin `GattPeerSession.kt`) —
/// the central/client-role connection to one peer.
///
/// Architectural difference from the Kotlin source: Kotlin drives a manual
/// `BluetoothGattCallback` state machine (connect → wait for
/// `onConnectionStateChange` → request MTU → wait for `onMtuChanged` →
/// discover services → wait for `onServicesDiscovered` → write the CCCD
/// descriptor → wait for `onDescriptorWrite` → ready). `universal_ble`
/// collapses each of those steps into a single awaited call
/// (`connect`/`requestMtu`/`discoverServices`/`subscribeNotifications`), so
/// this port is a linear `async` sequence instead of a callback state
/// machine — same steps, same order, same failure semantics (any step
/// failing moves to [PeerSessionState.failed] and fails [awaitReady]).
enum PeerSessionState { connecting, negotiating, ready, disconnected, failed }

class GattPeerSession {
  GattPeerSession._(this.deviceId);

  final String deviceId;
  int mtu = 23;

  PeerSessionState _state = PeerSessionState.connecting;
  PeerSessionState get state => _state;

  final StreamController<PeerSessionState> _stateController =
      StreamController<PeerSessionState>.broadcast();
  Stream<PeerSessionState> get stateStream => _stateController.stream;

  Stream<Uint8List> get incoming =>
      UniversalBle.characteristicValueStream(deviceId, MeshGatt.tx);

  final Completer<void> _ready = Completer<void>();
  final AsyncLock _writeLock = AsyncLock();
  StreamSubscription<bool>? _connectionSubscription;

  static GattPeerSession open(String deviceId) {
    final session = GattPeerSession._(deviceId);
    unawaited(session._connect());
    return session;
  }

  Future<void> _connect() async {
    try {
      _connectionSubscription = UniversalBle.connectionStream(deviceId).listen((
        connected,
      ) {
        if (!connected) _markDisconnected();
      });
      await UniversalBle.connect(deviceId);
      _setState(PeerSessionState.negotiating);
      try {
        mtu = await UniversalBle.requestMtu(deviceId, 517);
      } catch (_) {
        // MTU requests are best-effort; fall back to the default ATT MTU.
        mtu = 23;
      }
      await UniversalBle.discoverServices(deviceId);
      await UniversalBle.subscribeNotifications(
        deviceId,
        MeshGatt.service,
        MeshGatt.tx,
      );
      _setState(PeerSessionState.ready);
      _ready.complete();
    } catch (error) {
      _setState(PeerSessionState.failed);
      if (!_ready.isCompleted) _ready.completeError(error);
    }
  }

  Future<void> awaitReady() => _ready.future;

  Future<void> send(Uint8List bytes, {bool withResponse = true}) async {
    await _writeLock.synchronized(() async {
      await awaitReady();
      await UniversalBle.write(
        deviceId,
        MeshGatt.service,
        MeshGatt.rx,
        bytes,
        withoutResponse: !withResponse,
      );
    });
  }

  Future<void> close() async {
    _markDisconnected();
    try {
      await UniversalBle.disconnect(deviceId);
    } finally {
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      await _stateController.close();
    }
  }

  void _markDisconnected() {
    if (_state == PeerSessionState.disconnected) return;
    _setState(PeerSessionState.disconnected);
    if (!_ready.isCompleted) {
      _ready.completeError(StateError('GATT disconnected'));
    }
  }

  void _setState(PeerSessionState value) {
    _state = value;
    if (!_stateController.isClosed) _stateController.add(value);
  }
}
