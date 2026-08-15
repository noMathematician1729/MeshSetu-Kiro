import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// Port of `in.meshsetu.ble.MeshGatt` (Kotlin `MeshGatt.kt`).
///
/// Project-specific UUIDs; do not replace these with a vendor UART service.
abstract final class MeshGatt {
  static const String service = '2a6f5f10-4f7b-4c46-8cc8-cf282e4f4c01';
  static const String rx = '2a6f5f11-4f7b-4c46-8cc8-cf282e4f4c01';
  static const String tx = '2a6f5f12-4f7b-4c46-8cc8-cf282e4f4c01';
  static const int discoveryVersion = 1;

  /// The Kotlin source manually declares a CCCD descriptor on [tx] so raw
  /// Android `BluetoothGattServer` APIs can react to subscription writes.
  /// `universal_ble` manages the client characteristic configuration
  /// descriptor internally for `notify` characteristics, so no descriptor is
  /// declared here — see `gatt_server.dart`'s subscription handling instead.
  static BlePeripheralService buildService() => BlePeripheralService(
    uuid: service,
    primary: true,
    characteristics: [
      BlePeripheralCharacteristic(
        uuid: rx,
        properties: const [CharacteristicProperty.write],
        permissions: const [PeripheralAttributePermission.writeable],
      ),
      BlePeripheralCharacteristic(
        uuid: tx,
        properties: const [CharacteristicProperty.notify],
        permissions: const [PeripheralAttributePermission.readable],
      ),
    ],
  );
}

class DiscoveryMetadata {
  const DiscoveryMetadata({
    required this.fingerprint,
    required this.connectionToken,
    required this.capabilities,
  });

  final int fingerprint;
  final int connectionToken;
  final int capabilities;

  Uint8List encode() {
    final out = ByteData(14);
    out.setUint8(0, MeshGatt.discoveryVersion);
    out.setInt64(1, fingerprint, Endian.big);
    out.setUint32(9, connectionToken, Endian.big);
    out.setUint8(13, capabilities);
    return out.buffer.asUint8List();
  }

  static DiscoveryMetadata? decode(Uint8List bytes) {
    if (bytes.length != 14 || bytes[0] != MeshGatt.discoveryVersion) {
      return null;
    }
    final input = ByteData.sublistView(bytes);
    return DiscoveryMetadata(
      fingerprint: input.getInt64(1, Endian.big),
      connectionToken: input.getUint32(9, Endian.big),
      capabilities: input.getUint8(13),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DiscoveryMetadata &&
      other.fingerprint == fingerprint &&
      other.connectionToken == connectionToken &&
      other.capabilities == capabilities;

  @override
  int get hashCode => Object.hash(fingerprint, connectionToken, capabilities);
}

/// Deterministic tie-break for who initiates a GATT connection when two
/// peers discover each other simultaneously. Ties resolve to `false`; the
/// caller applies a randomized backoff on the vanishingly rare tie.
bool shouldInitiate(int localToken, int remoteToken) =>
    localToken < remoteToken;
