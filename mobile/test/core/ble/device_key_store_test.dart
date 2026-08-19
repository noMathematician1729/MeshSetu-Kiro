import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/device_key_store.dart';

class _FakeDeviceKeyStorage implements DeviceKeyStorage {
  String? value;
  bool failFirstRead = false;
  bool failDelete = false;
  int deleteCalls = 0;
  int writeCalls = 0;

  @override
  Future<void> delete({required String key}) async {
    deleteCalls++;
    if (failDelete) {
      throw PlatformException(code: 'keystore_unavailable');
    }
    value = null;
  }

  @override
  Future<String?> read({required String key}) async {
    if (failFirstRead) {
      failFirstRead = false;
      throw PlatformException(code: 'keystore_invalidated');
    }
    return value;
  }

  @override
  Future<void> write({required String key, required String value}) async {
    writeCalls++;
    this.value = value;
  }
}

void main() {
  tearDown(() => DeviceKeyStore.storageOverride = null);

  test('returns a valid persisted site key without replacing it', () async {
    final storage = _FakeDeviceKeyStorage()
      ..value = base64Encode(List<int>.filled(32, 4));
    DeviceKeyStore.storageOverride = storage;

    final key = await DeviceKeyStore.getOrCreateSiteKey(
      'test-site',
      List<int>.filled(32, 9),
    );

    expect(key, List<int>.filled(32, 4));
    expect(storage.deleteCalls, 0);
    expect(storage.writeCalls, 0);
  });

  test(
    'restores the supplied site key after a Keystore read failure',
    () async {
      final storage = _FakeDeviceKeyStorage()..failFirstRead = true;
      DeviceKeyStore.storageOverride = storage;
      final provisionedKey = List<int>.filled(32, 9);

      final key = await DeviceKeyStore.getOrCreateSiteKey(
        'test-site',
        provisionedKey,
      );

      expect(key, provisionedKey);
      expect(storage.deleteCalls, 1);
      expect(storage.writeCalls, 1);
      expect(base64Decode(storage.value!), provisionedKey);
    },
  );

  test(
    'reports an actionable error when secure storage cannot be recovered',
    () async {
      final storage = _FakeDeviceKeyStorage()
        ..failFirstRead = true
        ..failDelete = true;
      DeviceKeyStore.storageOverride = storage;

      await expectLater(
        DeviceKeyStore.getOrCreateSiteKey('test-site', List<int>.filled(32, 9)),
        throwsA(
          isA<DeviceKeyStoreException>().having(
            (error) => error.userMessage,
            'userMessage',
            contains('Unlock the phone'),
          ),
        ),
      );
    },
  );
}
