import 'dart:async';

import 'package:flutter/services.dart';

/// A best-effort location captured at SOS creation time.
final class SosLocation {
  const SosLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.capturedAtMs,
  });

  final double latitude;
  final double longitude;
  final double? accuracyM;
  final int capturedAtMs;

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

enum LocationFailureReason {
  permissionDenied,
  servicesDisabled,
  noFix,
  timedOut,
  unavailable,
}

extension LocationFailureReasonMessage on LocationFailureReason {
  String get message => switch (this) {
    LocationFailureReason.permissionDenied =>
      'Location permission denied · allow it in Settings',
    LocationFailureReason.servicesDisabled =>
      'Location services are off · turn Location on',
    LocationFailureReason.noFix =>
      'No location fix · try again outdoors or set an emulator location',
    LocationFailureReason.timedOut =>
      'Location timed out · try again with Location on',
    LocationFailureReason.unavailable => 'Location unavailable',
  };
}

final class LocationCaptureResult {
  const LocationCaptureResult.success(this.location) : failure = null;

  const LocationCaptureResult.failure(this.failure) : location = null;

  final SosLocation? location;
  final LocationFailureReason? failure;

  String get status => location != null
      ? 'Location attached'
      : failure?.message ?? LocationFailureReason.unavailable.message;
}

/// Uses the platform location provider without adding another location SDK.
/// Android is implemented now; unsupported platforms report unavailable.
final class LocationCapture {
  const LocationCapture();

  static const _channel = MethodChannel('meshsetu/location');

  Future<LocationCaptureResult> capture({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('getCurrentLocation')
          .timeout(timeout);
      if (raw == null) {
        return const LocationCaptureResult.failure(
          LocationFailureReason.unavailable,
        );
      }
      if (raw['ok'] == false) {
        return LocationCaptureResult.failure(_failureFor(raw['reason']));
      }
      final latitude = (raw['latitude'] as num?)?.toDouble();
      final longitude = (raw['longitude'] as num?)?.toDouble();
      if (latitude == null || longitude == null) {
        return const LocationCaptureResult.failure(
          LocationFailureReason.unavailable,
        );
      }
      final location = SosLocation(
        latitude: latitude,
        longitude: longitude,
        accuracyM: (raw['accuracyM'] as num?)?.toDouble(),
        capturedAtMs:
            (raw['capturedAtMs'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      );
      return location.isValid
          ? LocationCaptureResult.success(location)
          : const LocationCaptureResult.failure(
              LocationFailureReason.unavailable,
            );
    } on PlatformException {
      return const LocationCaptureResult.failure(
        LocationFailureReason.unavailable,
      );
    } on MissingPluginException {
      return const LocationCaptureResult.failure(
        LocationFailureReason.unavailable,
      );
    } on TimeoutException {
      return const LocationCaptureResult.failure(
        LocationFailureReason.timedOut,
      );
    }
  }

  static LocationFailureReason _failureFor(Object? value) => switch (value) {
    'permission_denied' => LocationFailureReason.permissionDenied,
    'services_disabled' => LocationFailureReason.servicesDisabled,
    'no_fix' => LocationFailureReason.noFix,
    'timeout' => LocationFailureReason.timedOut,
    _ => LocationFailureReason.unavailable,
  };
}
