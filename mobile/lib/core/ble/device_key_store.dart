import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Port of `in.meshsetu.ble.DeviceKeyStore` (Kotlin `DeviceKeyStore.kt`).
///
/// Architecture change from the Kotlin source, not a literal port: Kotlin
/// generates an AES-256 key *inside* AndroidKeystore and hands back a
/// `javax.crypto.SecretKey` handle that `Cipher` can use directly without the
/// raw bytes ever leaving the keystore. Dart's `cryptography` package (used
/// by `secure_envelope.dart`) has no equivalent HSM-backed key handle — it
/// only accepts raw key bytes. So, per the Bible's own §16.2 guidance, this
/// generates a random 256-bit key once and stores/retrieves it as bytes via
/// `flutter_secure_storage`, which is itself Keystore/EncryptedSharedPreferences-backed
/// on Android. `AeadEnvelope` consumes the returned bytes unchanged.
abstract final class DeviceKeyStore {
  static const String defaultAlias = 'meshsetu_device_wrap';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<List<int>> getOrCreate({String alias = defaultAlias}) async {
    final existing = await _storage.read(key: alias);
    if (existing != null) return base64Decode(existing);
    final key = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    await _storage.write(key: alias, value: base64Encode(key));
    return key;
  }
}
