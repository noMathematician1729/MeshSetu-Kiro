import 'dart:async';

import 'package:flutter/foundation.dart';
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
  // A rejected client can remain subscribed on the radio. Keep that fact
  // separate so a freed slot can restore admission without a second CCCD write.
  final Set<String> _knownSubscribers = {};
  final Set<String> _rejectedPeers = {};
  int _pendingFrames = 0;
  bool _running = false;
  // universal_ble mutates one characteristic value before posting the native
  // notify call. Keep this lock global or two devices can receive the later
  // frame's bytes when those posted callbacks run out of order.
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
    _rejectedPeers.clear();
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
      if (_rejectedPeers.contains(deviceId)) {
        return PeripheralWriteRequestResult(status: _gattFailure);
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
            _knownSubscribers.add(event.deviceId);
            if (_rejectedPeers.contains(event.deviceId)) return;
            _subscribers.add(event.deviceId);
          } else {
            _subscribers.remove(event.deviceId);
            _knownSubscribers.remove(event.deviceId);
            _rejectedPeers.remove(event.deviceId);
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

  bool isPeerRejected(String deviceId) => _rejectedPeers.contains(deviceId);

  Iterable<String> get rejectedPeerIds =>
      List<String>.unmodifiable(_rejectedPeers);

  /// The plugin cannot disconnect a peripheral client, so reject it at the
  /// write/subscription boundary until capacity admission is restored or the
  /// client unsubscribes.
  void rejectPeer(String deviceId) {
    _rejectedPeers.add(deviceId);
    _subscribers.remove(deviceId);
  }

  Future<void> disconnectPeer(String deviceId) async {
    try {
      await UniversalBlePeripheral.disconnectPeripheral(deviceId);
    } catch (_) {
      // Logical rejection remains in force when the platform cannot cancel
      // the peripheral connection.
    }
  }

  /// Re-admits a client that is still subscribed after a slot opens.
  bool admitPeer(String deviceId) {
    if (!_rejectedPeers.remove(deviceId)) return false;
    if (_running && _knownSubscribers.contains(deviceId)) {
      _subscribers.add(deviceId);
    }
    return true;
  }

  /// Serializes notifications and waits for Android's native
  /// BluetoothGattCallback completion status. Other platforms return after
  /// their plugin operation completes because this app's Android callback is
  /// not available there.
  Future<bool> notifyAwait(String deviceId, Uint8List bytes) async {
    if (!_running || bytes.isEmpty || !_subscribers.contains(deviceId)) {
      return false;
    }
    return _notifyLock.synchronized(() async {
      if (!_running || !_subscribers.contains(deviceId)) return false;
      final expected = Uint8List.fromList(bytes);
      final completion = defaultTargetPlatform == TargetPlatform.android
          ? UniversalBlePeripheral.notificationSentStream
                .where(
                  (event) =>
                      event.deviceId == deviceId &&
                      event.value != null &&
                      listEquals(event.value, expected),
                )
                .first
          : null;
      try {
        await UniversalBlePeripheral.updateCharacteristicValue(
          characteristicId: MeshGatt.tx,
          value: bytes,
          deviceId: deviceId,
        ).timeout(const Duration(seconds: 2));
      } catch (_) {
        return false;
      }
      if (completion == null) return true;
      try {
        return (await completion.timeout(const Duration(seconds: 2))).status ==
            0;
      } catch (_) {
        return false;
      }
    });
  }

  Future<void> stop() async {
    _running = false;
    UniversalBlePeripheral.setWriteRequestHandlers(null);
    await _subscriptionSubscription?.cancel();
    _subscriptionSubscription = null;
    await _mtuSubscription?.cancel();
    _mtuSubscription = null;
    await _notifyLock.idle;
    await UniversalBlePeripheral.clearServices();
    _subscribers.clear();
    _knownSubscribers.clear();
    _rejectedPeers.clear();
    _mtus.clear();
    _pendingFrames = 0;
    await _frames.close();
  }
}
