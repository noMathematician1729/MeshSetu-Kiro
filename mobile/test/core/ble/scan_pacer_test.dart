import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/scan_pacer.dart';

class _FakeClock {
  int nowMs = 0;
  int call() => nowMs;
}

void main() {
  test('allows scan starts under the rolling-window cap', () {
    final clock = _FakeClock();
    final pacer = ScanPacer(maxStartsPerWindow: 5, nowMs: clock.call);

    for (var i = 0; i < 5; i++) {
      expect(pacer.isThrottled, isFalse);
      pacer.recordScanStart();
      clock.nowMs += 1000;
    }

    expect(pacer.isThrottled, isTrue);
  });

  test('throttle state ages out once the rolling window passes', () {
    final clock = _FakeClock();
    final pacer = ScanPacer(
      maxStartsPerWindow: 2,
      throttleWindow: const Duration(seconds: 30),
      nowMs: clock.call,
    );

    pacer.recordScanStart();
    clock.nowMs += 1000;
    pacer.recordScanStart();
    expect(pacer.isThrottled, isTrue);

    clock.nowMs += 31000;
    expect(pacer.isThrottled, isFalse);
  });

  test('deferred idle duration is the max idle window while throttled', () {
    final clock = _FakeClock();
    final pacer = ScanPacer(
      maxStartsPerWindow: 1,
      maxIdleWindow: const Duration(seconds: 20),
      nowMs: clock.call,
    );

    pacer.recordScanStart();
    expect(pacer.isThrottled, isTrue);
    expect(pacer.nextIdleDuration(), const Duration(seconds: 20));
  });

  test('idle duration stays at base while under the blind-cycle threshold', () {
    final pacer = ScanPacer(
      blindCyclesBeforeBackoff: 2,
      baseIdleWindow: const Duration(seconds: 2),
    );

    pacer.recordCycleResult(devicesSeen: 0);
    expect(pacer.nextIdleDuration(), const Duration(seconds: 2));
  });

  test('idle duration backs off after consecutive blind cycles', () {
    final pacer = ScanPacer(
      blindCyclesBeforeBackoff: 2,
      baseIdleWindow: const Duration(seconds: 2),
      maxIdleWindow: const Duration(seconds: 20),
    );

    pacer.recordCycleResult(devicesSeen: 0);
    pacer.recordCycleResult(devicesSeen: 0);
    final firstBackoff = pacer.nextIdleDuration();
    expect(firstBackoff, greaterThan(const Duration(seconds: 2)));

    pacer.recordCycleResult(devicesSeen: 0);
    final secondBackoff = pacer.nextIdleDuration();
    expect(secondBackoff, greaterThan(firstBackoff));
    expect(secondBackoff, lessThanOrEqualTo(const Duration(seconds: 20)));
  });

  test('a non-blind cycle resets backoff back to the base idle window', () {
    final pacer = ScanPacer(
      blindCyclesBeforeBackoff: 1,
      baseIdleWindow: const Duration(seconds: 2),
    );

    pacer.recordCycleResult(devicesSeen: 0);
    expect(pacer.nextIdleDuration(), greaterThan(const Duration(seconds: 2)));

    pacer.recordCycleResult(devicesSeen: 3);
    expect(pacer.nextIdleDuration(), const Duration(seconds: 2));
  });

  test('idle backoff never exceeds maxIdleWindow', () {
    final pacer = ScanPacer(
      blindCyclesBeforeBackoff: 1,
      baseIdleWindow: const Duration(seconds: 2),
      maxIdleWindow: const Duration(seconds: 10),
    );

    for (var i = 0; i < 10; i++) {
      pacer.recordCycleResult(devicesSeen: 0);
    }

    expect(pacer.nextIdleDuration(), const Duration(seconds: 10));
  });
}
