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
  final Set<String> _connectedPeers = {};
  final Set<String> _observedConnectionStates = {};
  final Set<String> _reconnectRequests = {};
  int _pendingFrames = 0;
  int _notificationSequence = 0;
  bool _running = false;
  // universal_ble mutates one characteristic value before posting the native
  // notify call. Keep this lock global or two devices can receive the later
  // frame's bytes when those posted callbacks run out of order.
  final AsyncLock _notifyLock = AsyncLock();
  StreamSubscription<BlePeripheralCharacteristicSubscriptionChanged>?
  _subscriptionSubscription;
  StreamSubscription<BlePeripheralMtuChanged>? _mtuSubscription;
  StreamSubscription<BlePeripheralConnectionStateChanged>?
  _connectionSubscription;
  final Map<String, int> _mtus = {};

  Stream<IncomingGattFrame> get incoming => _frames.stream;

  Stream<String> get subscribedPeerIds => UniversalBlePeripheral
      .characteristicSubscriptionStream
      .where(
        (event) => event.characteristicId == MeshGatt.tx && event.isSubscribed,
      )
      .map((event) => event.deviceId);

  Stream<String> get unsubscribedPeerIds => UniversalBlePeripheral
      .characteristicSubscriptionStream
      .where(
        (event) => event.characteristicId == MeshGatt.tx && !event.isSubscribed,
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
    int? maximumNotifyLength;
    try {
      maximumNotifyLength = await UniversalBlePeripheral.getMaximumNotifyLength(
        deviceId,
      );
    } catch (_) {
      // A reconnect can race the platform's MTU cache; use the ATT default
      // and let the next MTU callback refine it.
    }
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
      if (_rejectedPeers.contains(deviceId) ||
          !_subscribers.contains(deviceId)) {
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
            // A fresh subscription is the client's retry after a capacity
            // disconnect. It is safe to let the coordinator re-run its
            // capacity check from this event.
            _rejectedPeers.remove(event.deviceId);
            _reconnectRequests.remove(event.deviceId);
            _subscribers.add(event.deviceId);
          } else {
            _subscribers.remove(event.deviceId);
            _knownSubscribers.remove(event.deviceId);
            // Keep a capacity rejection across the disconnect so a freed
            // slot can request a reconnect instead of losing the peer.
            if (!_rejectedPeers.contains(event.deviceId)) {
              _reconnectRequests.remove(event.deviceId);
            }
          }
        });

    _connectionSubscription = UniversalBlePeripheral.connectionStateStream
        .listen((event) {
          _observedConnectionStates.add(event.deviceId);
          if (event.connected) {
            _connectedPeers.add(event.deviceId);
          } else {
            _connectedPeers.remove(event.deviceId);
            _mtus.remove(event.deviceId);
          }
        });

    _mtuSubscription = UniversalBlePeripheral.mtuChangedStream.listen((event) {
      _mtus[event.deviceId] = event.mtu;
    });

    // Android's addService is asynchronous. Advertising before its callback
    // lets a peer connect to an empty GATT database and fail discovery.
    final serviceAdded = UniversalBlePeripheral.serviceAddedStream
        .firstWhere(
          (event) => event.serviceId.toLowerCase() == MeshGatt.service,
        )
        .timeout(const Duration(seconds: 3));
    await UniversalBlePeripheral.addService(MeshGatt.buildService());
    final added = await serviceAdded;
    if (added.error != null) {
      throw StateError('Mesh GATT service registration failed: ${added.error}');
    }
  }

  /// Releases one slot from the bounded receive queue after the coordinator
  /// has finished processing a frame.
  void acknowledge(IncomingGattFrame frame) {
    if (_pendingFrames > 0) _pendingFrames--;
  }

  bool isPeerRejected(String deviceId) => _rejectedPeers.contains(deviceId);

  /// Whether the rejected client still has its CCCD subscription. Test and
  /// non-Android implementations do not always expose connection callbacks,
  /// so a subscription is treated as live until a platform state says it is
  /// disconnected.
  bool hasLiveSubscription(String deviceId) {
    if (!_knownSubscribers.contains(deviceId)) return false;
    return !_observedConnectionStates.contains(deviceId) ||
        _connectedPeers.contains(deviceId);
  }

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

  /// Asks Android's GATT server to reconnect a capacity-rejected client. The
  /// client must still complete its normal CCCD subscription before admission.
  Future<void> reconnectPeer(String deviceId) async {
    if (!_rejectedPeers.contains(deviceId) ||
        hasLiveSubscription(deviceId) ||
        !_reconnectRequests.add(deviceId)) {
      return;
    }
    try {
      await UniversalBlePeripheral.reconnectPeripheral(deviceId);
    } catch (_) {
      _reconnectRequests.remove(deviceId);
    }
  }

  /// Re-admits a client that is still subscribed after a slot opens.
  bool admitPeer(String deviceId) {
    if (!_rejectedPeers.remove(deviceId)) return false;
    _reconnectRequests.remove(deviceId);
    if (_running && hasLiveSubscription(deviceId)) {
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
      final notificationId = ++_notificationSequence;
      Future<BlePeripheralNotificationSent>? completion;
      StreamSubscription<BlePeripheralNotificationSent>? completionSubscription;
      if (defaultTargetPlatform == TargetPlatform.android) {
        final completionFuture = Completer<BlePeripheralNotificationSent>();
        completionSubscription = UniversalBlePeripheral.notificationSentStream
            .where(
              (event) =>
                  event.deviceId == deviceId &&
                  event.notificationId == notificationId,
            )
            .listen((event) {
              if (!completionFuture.isCompleted) {
                completionFuture.complete(event);
              }
            });
        completion = completionFuture.future;
      }
      try {
        await UniversalBlePeripheral.updateCharacteristicValueWithId(
          characteristicId: MeshGatt.tx,
          value: bytes,
          notificationId: notificationId,
          deviceId: deviceId,
        ).timeout(const Duration(seconds: 2));
      } catch (_) {
        await completionSubscription?.cancel();
        return false;
      }
      if (completion == null) return true;
      try {
        return (await completion.timeout(const Duration(seconds: 2))).status ==
            0;
      } catch (_) {
        return false;
      } finally {
        await completionSubscription?.cancel();
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
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _notifyLock.idle;
    await UniversalBlePeripheral.clearServices();
    _subscribers.clear();
    _knownSubscribers.clear();
    _rejectedPeers.clear();
    _connectedPeers.clear();
    _observedConnectionStates.clear();
    _reconnectRequests.clear();
    _mtus.clear();
    _pendingFrames = 0;
    await _frames.close();
  }
}
