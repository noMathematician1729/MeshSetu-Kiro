import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

sealed class BlePeripheralEvent {}

class BlePeripheralAdvertisingStateChanged extends BlePeripheralEvent {
  final PeripheralAdvertisingState state;
  final String? error;
  BlePeripheralAdvertisingStateChanged(this.state, this.error);
}

class BlePeripheralCharacteristicSubscriptionChanged
    extends BlePeripheralEvent {
  final String deviceId;
  final String characteristicId;
  final bool isSubscribed;
  final String? name;

  BlePeripheralCharacteristicSubscriptionChanged({
    required this.deviceId,
    required this.characteristicId,
    required this.isSubscribed,
    required this.name,
  });
}

class BlePeripheralConnectionStateChanged extends BlePeripheralEvent {
  final String deviceId;
  final bool connected;
  BlePeripheralConnectionStateChanged(this.deviceId, this.connected);
}

class BlePeripheralServiceAdded extends BlePeripheralEvent {
  final String serviceId;
  final String? error;
  BlePeripheralServiceAdded(this.serviceId, this.error);
}

class BlePeripheralMtuChanged extends BlePeripheralEvent {
  final String deviceId;
  final int mtu;
  BlePeripheralMtuChanged(this.deviceId, this.mtu);
}

class BlePeripheralNotificationSent extends BlePeripheralEvent {
  final String deviceId;
  final int status;
  final Uint8List? value;

  BlePeripheralNotificationSent(this.deviceId, this.status, this.value);
}
