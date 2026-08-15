import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Port of `in.meshsetu.ble.DeviceKeyStore` / `SiteKeyProvisioning` (Kotlin
/// `DeviceKeyStore.kt`).
///
/// Architecture change from the Kotlin source, not a literal port: Kotlin
/// generates an AES-256 key *inside* AndroidKeystore and hands back a
/// `javax.crypto.SecretKey` handle that `Cipher` can use directly without the
/// raw bytes ever leaving the keystore, then manually AES-GCM-wraps a
/// provisioned site key with that device key before persisting it to
/// SharedPreferences. Dart's `cryptography` package (used by
/// `secure_envelope.dart`) has no equivalent HSM-backed key handle — it only
/// accepts raw key bytes. `flutter_secure_storage` already *is* the "wrap
/// with a device-backed key" primitive on Android (Keystore/
/// EncryptedSharedPreferences), so there's no need for a second manual wrap
/// layer around it: keys are simply stored as base64 directly.
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

  /// Returns the shared site key for [siteId], provisioning it with
  /// [provisionedKey] on first use.
  static Future<List<int>> getOrCreateSiteKey(
    String siteId,
    List<int> provisionedKey,
  ) async {
    if (![16, 24, 32].contains(provisionedKey.length)) {
      throw ArgumentError('site key must be AES-sized');
    }
    final alias = _siteAlias(siteId);
    final existing = await _storage.read(key: alias);
    if (existing != null) return base64Decode(existing);
    await _storage.write(key: alias, value: base64Encode(provisionedKey));
    return provisionedKey;
  }

  static String _siteAlias(String siteId) {
    final digest = sha256.convert(utf8.encode(siteId)).bytes;
    final prefix = digest
        .sublist(0, 8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'meshsetu_site_$prefix';
  }
}

/// Development-only bootstrap; production provisioning must supply a signed
/// manifest key.
abstract final class SiteKeyProvisioning {
  static List<int> demoKey(String siteId) =>
      sha256.convert(utf8.encode('MeshSetu-demo-site-key-v1:$siteId')).bytes;
}
