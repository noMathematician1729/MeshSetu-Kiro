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
  final AsyncLock _notifyLock = AsyncLock();
  StreamSubscription<BlePeripheralCharacteristicSubscriptionChanged>?
  _subscriptionSubscription;

  Stream<IncomingGattFrame> get incoming => _frames.stream;

  Future<void> start() async {
    UniversalBlePeripheral.setWriteRequestHandlers((
      deviceId,
      characteristicId,
      offset,
      value,
    ) {
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

    await UniversalBlePeripheral.addService(MeshGatt.buildService());
  }

  /// Releases one slot from the bounded receive queue after the coordinator
  /// has finished processing a frame.
  void acknowledge(IncomingGattFrame frame) {
    if (_pendingFrames > 0) _pendingFrames--;
  }

  /// Renamed to match upstream's `notifyAwait` — `universal_ble`'s
  /// `updateCharacteristicValue` is itself an awaited platform call, so this
  /// already waits for the notification to actually go out, not just for
  /// the OS to accept the request.
  Future<bool> notifyAwait(String deviceId, Uint8List bytes) async {
    if (!_subscribers.contains(deviceId)) return false;
    return _notifyLock.synchronized(() async {
      if (!_subscribers.contains(deviceId)) return false;
      await UniversalBlePeripheral.updateCharacteristicValue(
        characteristicId: MeshGatt.tx,
        value: bytes,
        deviceId: deviceId,
      );
      return true;
    });
  }

  Future<void> stop() async {
    await _subscriptionSubscription?.cancel();
    _subscriptionSubscription = null;
    await UniversalBlePeripheral.clearServices();
    _subscribers.clear();
    _pendingFrames = 0;
    await _frames.close();
  }
}
