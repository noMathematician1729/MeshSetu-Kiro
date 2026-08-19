import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'onboarding_profile.dart';

abstract interface class OnboardingStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

final class SecureOnboardingStorage implements OnboardingStorage {
  SecureOnboardingStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'meshsetu.onboarding.profile.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Small deterministic implementation for unit tests. It intentionally has
/// the same asynchronous API as secure storage so tests do not alter app flow.
final class MemoryOnboardingStorage implements OnboardingStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String next) async => value = next;

  @override
  Future<void> delete() async => value = null;
}

final class OnboardingRepository {
  OnboardingRepository([OnboardingStorage? storage])
    : _storage = storage ?? SecureOnboardingStorage();

  final OnboardingStorage _storage;

  Future<OnboardingProfile?> load() async {
    final encoded = await _storage.read();
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      final profile = OnboardingProfile.fromJson(
        decoded.cast<String, Object?>(),
      );
      if (!profile.isValid) return null;
      final uid = _reporterUid(profile);
      return profile.reporterUid == uid
          ? profile
          : profile.withReporterUid(uid);
    } on FormatException {
      return null;
    }
  }

  Future<void> save(OnboardingProfile profile) async {
    final error = profile.validationError;
    if (error != null) throw ArgumentError(error);
    final normalized = profile.withReporterUid(_reporterUid(profile));
    await _storage.write(jsonEncode(normalized.toJson()));
  }

  Future<bool> isOnboarded() async => await load() != null;

  Future<void> clear() => _storage.delete();

  String _reporterUid(OnboardingProfile profile) {
    final material = utf8.encode(
      '${profile.profileId}:${profile.phone.replaceAll(RegExp(r'[^0-9+]'), '')}',
    );
    final digest = sha256.convert(material).bytes;
    return Uint8List.fromList(digest.take(6).toList())
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
