import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

/// Port of `in.meshsetu.ble.MeshGatt` (Kotlin `MeshGatt.kt`).
///
/// Project-specific UUIDs; do not replace these with a vendor UART service.
abstract final class MeshGatt {
  static const String service = '2a6f5f10-4f7b-4c46-8cc8-cf282e4f4c01';
  static const String rx = '2a6f5f11-4f7b-4c46-8cc8-cf282e4f4c01';
  static const String tx = '2a6f5f12-4f7b-4c46-8cc8-cf282e4f4c01';
  static const String cccd = '00002902-0000-1000-8000-00805f9b34fb';
  static const int discoveryVersion = 1;
  // ATT MTU 517 leaves 514 bytes for a notification, but a GATT
  // characteristic value itself is capped at 512 bytes by Android.
  static const int maxAttributeValueBytes = 512;

  /// Bluetooth SIG's reserved "for testing" company identifier.
  static const int developmentManufacturerId = 0xFFFF;
  static const int manufacturerId = int.fromEnvironment(
    'MESHSETU_BLE_COMPANY_ID',
    defaultValue: developmentManufacturerId,
  );
  static const int discoveryPayloadType = 1;
  static const int sosPayloadType = 2;
  static const int beaconPayloadType = 3;
  static const int beaconVersion = 1;

  static bool isProductionCompanyId(int value) =>
      value >= 0 && value < developmentManufacturerId;

  static void validateCompanyId() {
    if (kReleaseMode && !isProductionCompanyId(manufacturerId)) {
      throw StateError(
        'Release builds require --dart-define='
        'MESHSETU_BLE_COMPANY_ID=<assigned Bluetooth SIG company ID>',
      );
    }
  }

  static Uint8List manufacturerPayload(int type, Uint8List payload) =>
      Uint8List.fromList([type, ...payload]);

  static Uint8List? payloadForType(Uint8List payload, int type) =>
      payload.isNotEmpty && payload.first == type
      ? Uint8List.sublistView(payload, 1)
      : null;

  static int siteFingerprint(String siteId, {String namespace = 'demo'}) {
    final digest = sha256.convert(utf8.encode('$siteId|$namespace')).bytes;
    return ByteData.sublistView(
      Uint8List.fromList(digest.sublist(0, 8)),
    ).getInt64(0, Endian.big);
  }

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

class BeaconMetadata {
  const BeaconMetadata(this.anchorId);

  final String anchorId;

  Uint8List encode() {
    final bytes = Uint8List.fromList(utf8.encode(anchorId));
    if (bytes.isEmpty || bytes.length > 24) {
      throw ArgumentError('anchorId must be 1..24 UTF-8 bytes');
    }
    return Uint8List.fromList([MeshGatt.beaconVersion, ...bytes]);
  }

  static BeaconMetadata? decode(Uint8List bytes) {
    if (bytes.length < 2 || bytes.first != MeshGatt.beaconVersion) return null;
    final String anchorId;
    try {
      anchorId = utf8.decode(bytes.sublist(1), allowMalformed: false);
    } on FormatException {
      return null;
    }
    if (anchorId.isEmpty || utf8.encode(anchorId).length > 24) return null;
    return BeaconMetadata(anchorId);
  }
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
