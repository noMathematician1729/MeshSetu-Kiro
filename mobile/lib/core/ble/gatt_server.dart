import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'async_lock.dart';
import 'mesh_gatt.dart';

/// Android's `BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED`, mirrored here since
/// `universal_ble` exposes raw status ints rather than the Android constant.
const int _gattRequestNotSupported = 3;
const int _gattFailure = 1;
const int _maxPendingFrames = 64;

class IncomingGattFrame {
  const IncomingGattFrame({required this.deviceId, required this.bytes});

  final String deviceId;
  final Uint8List bytes;
}

/// Port of `in.meshsetu.ble.MeshGattServer` (Kotlin `GattServer.kt`) — the
/// peripheral/server role that receives frames and notifies subscribers.
///
/// Deviation from the Kotlin source: Kotlin tracks subscribers manually by
/// handling the raw CCCD descriptor write (`onDescriptorWriteRequest`).
/// `universal_ble` manages the CCCD internally and instead reports
/// subscription changes via `characteristicSubscriptionStream`
/// (`BlePeripheralCharacteristicSubscriptionChanged`), which this class
/// listens to instead — same resulting `_subscribers` set, no descriptor
/// plumbing needed. There's also no `preparedWrite` flag in
/// `universal_ble`'s write-request handler (the plugin handles prepared
/// writes internally), so that check from the Kotlin source is dropped.
class MeshGattServer {
  final StreamController<IncomingGattFrame> _frames =
      StreamController<IncomingGattFrame>.broadcast();
  final Set<String> _subscribers = {};
  int _pendingFrames = 0;
  bool _running = false;
  final AsyncLock _notifyLock = AsyncLock();
  StreamSubscription<BlePeripheralCharacteristicSubscriptionChanged>?
  _subscriptionSubscription;
  StreamSubscription<BlePeripheralMtuChanged>? _mtuSubscription;
  final Map<String, int> _mtus = {};

  Stream<IncomingGattFrame> get incoming => _frames.stream;

  Stream<String> get subscribedPeerIds => UniversalBlePeripheral
      .characteristicSubscriptionStream
      .where(
        (event) => event.characteristicId == MeshGatt.tx && event.isSubscribed,
      )
      .map((event) => event.deviceId);

  Stream<Uint8List> incomingFrom(String deviceId) => _frames.stream
      .where((frame) => frame.deviceId == deviceId)
      .map((frame) => frame.bytes);

  Stream<bool> connectionStateFor(String deviceId) => UniversalBlePeripheral
      .connectionStateStream
      .where((event) => event.deviceId == deviceId)
      .map((event) => event.connected);

  Future<int> mtuFor(String deviceId) async {
    final known = _mtus[deviceId];
    if (known != null) return known;
    final maximumNotifyLength =
        await UniversalBlePeripheral.getMaximumNotifyLength(deviceId);
    // universal_ble reports the ATT payload budget, while fragment() expects
    // the negotiated MTU including the three-byte notification header.
    return maximumNotifyLength == null || maximumNotifyLength < 20
        ? 23
        : maximumNotifyLength + 3;
  }

  Future<void> start() async {
    _running = true;
    UniversalBlePeripheral.setWriteRequestHandlers((
      deviceId,
      characteristicId,
      offset,
      value,
    ) {
      if (!_running) {
        return PeripheralWriteRequestResult(status: _gattFailure);
      }
      if (characteristicId != MeshGatt.rx || offset != 0 || value == null) {
        return PeripheralWriteRequestResult(status: _gattRequestNotSupported);
      }
      if (_pendingFrames >= _maxPendingFrames) {
        return PeripheralWriteRequestResult(status: _gattFailure);
      }
      _pendingFrames++;
      _frames.add(
        IncomingGattFrame(deviceId: deviceId, bytes: Uint8List.fromList(value)),
      );
      return null;
    });

    _subscriptionSubscription = UniversalBlePeripheral
        .characteristicSubscriptionStream
        .listen((event) {
          if (event.characteristicId != MeshGatt.tx) return;
          if (event.isSubscribed) {
            _subscribers.add(event.deviceId);
          } else {
            _subscribers.remove(event.deviceId);
          }
        });

    _mtuSubscription = UniversalBlePeripheral.mtuChangedStream.listen((event) {
      _mtus[event.deviceId] = event.mtu;
    });

    await UniversalBlePeripheral.addService(MeshGatt.buildService());
  }

  /// Releases one slot from the bounded receive queue after the coordinator
  /// has finished processing a frame.
  void acknowledge(IncomingGattFrame frame) {
    if (_pendingFrames > 0) _pendingFrames--;
  }

  /// Serializes notifications and applies conservative pacing because
  /// universal_ble does not expose Android's onNotificationSent callback.
  Future<bool> notifyAwait(String deviceId, Uint8List bytes) async {
    if (!_subscribers.contains(deviceId)) return false;
    return _notifyLock.synchronized(() async {
      if (!_subscribers.contains(deviceId)) return false;
      await UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: MeshGatt.tx,
        value: bytes,
        deviceId: deviceId,
      );
      // ponytail: replace this conservative pacing with onNotificationSent
      // when universal_ble exposes that platform callback.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return true;
    });
  }

  Future<void> stop() async {
    _running = false;
    UniversalBlePeripheral.setWriteRequestHandlers(null);
    await _subscriptionSubscription?.cancel();
    _subscriptionSubscription = null;
    await _mtuSubscription?.cancel();
    _mtuSubscription = null;
    await UniversalBlePeripheral.clearServices();
    _subscribers.clear();
    _mtus.clear();
    _pendingFrames = 0;
    await _frames.close();
  }
}
