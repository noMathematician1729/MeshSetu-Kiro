import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The subset of secure storage used by [DeviceKeyStore].
///
/// Keeping this small makes the Android Keystore failure path testable without
/// a platform channel.
abstract interface class DeviceKeyStorage {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class _FlutterDeviceKeyStorage implements DeviceKeyStorage {
  const _FlutterDeviceKeyStorage(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// Raised when Android Keystore-backed storage cannot be read or recreated.
/// Its message is safe to show in the event-mode UI; platform exceptions often
/// misleadingly say only "hardware error".
class DeviceKeyStoreException implements Exception {
  const DeviceKeyStoreException({this.cause});

  final Object? cause;

  String get userMessage =>
      'Secure device storage is unavailable. Unlock the phone, then retry '
      'event mode. If this continues after a restart, reinstall the app and '
      'rejoin the site.';

  @override
  String toString() => userMessage;
}

class _StoredKeyInvalid implements Exception {}

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
  static final DeviceKeyStorage _defaultStorage = _FlutterDeviceKeyStorage(
    const FlutterSecureStorage(),
  );

  @visibleForTesting
  static DeviceKeyStorage? storageOverride;

  static DeviceKeyStorage get _storage => storageOverride ?? _defaultStorage;

  static Future<List<int>> getOrCreate({String alias = defaultAlias}) {
    final key = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return _readOrRestore(alias, key);
  }

  /// Returns the shared site key for [siteId], provisioning it with
  /// [provisionedKey] on first use.
  ///
  /// An Android backup, lock-screen change, or Keystore reset can make the
  /// encrypted record undecryptable. In that case only this local record is
  /// removed and it is restored from the caller's authoritative provisioned
  /// key. We never substitute an unrelated random key for a site key.
  static Future<List<int>> getOrCreateSiteKey(
    String siteId,
    List<int> provisionedKey,
  ) async {
    if (![16, 24, 32].contains(provisionedKey.length)) {
      throw ArgumentError('site key must be AES-sized');
    }
    return _readOrRestore(_siteAlias(siteId), provisionedKey);
  }

  static Future<List<int>> _readOrRestore(
    String alias,
    List<int> replacement,
  ) async {
    try {
      final existing = await _storage.read(key: alias);
      if (existing != null) return _decodeAesKey(existing);
      await _writeAndConfirm(alias, replacement);
      return replacement;
    } on PlatformException catch (error) {
      return _restoreAfterStorageFailure(alias, replacement, error);
    } on _StoredKeyInvalid catch (error) {
      return _restoreAfterStorageFailure(alias, replacement, error);
    }
  }

  static Future<List<int>> _restoreAfterStorageFailure(
    String alias,
    List<int> replacement,
    Object cause,
  ) async {
    try {
      // A stale encrypted preference cannot be decrypted after its Keystore
      // key is invalidated. Delete only this app record, then persist the same
      // provisioned key again. A failed delete/write remains a user-visible,
      // retryable secure-storage error rather than a raw "hardware error".
      await _storage.delete(key: alias);
      await _writeAndConfirm(alias, replacement);
      return replacement;
    } catch (error) {
      throw DeviceKeyStoreException(cause: error);
    }
  }

  static Future<void> _writeAndConfirm(String alias, List<int> key) async {
    await _storage.write(key: alias, value: base64Encode(key));
    final persisted = await _storage.read(key: alias);
    if (persisted == null || !_sameBytes(_decodeAesKey(persisted), key)) {
      throw _StoredKeyInvalid();
    }
  }

  static List<int> _decodeAesKey(String encoded) {
    try {
      final key = base64Decode(encoded);
      if (![16, 24, 32].contains(key.length)) throw const FormatException();
      return key;
    } on FormatException {
      throw _StoredKeyInvalid();
    }
  }

  static bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
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
