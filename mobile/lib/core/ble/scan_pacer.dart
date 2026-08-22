/// Paces repeated BLE scan starts so the long-running discovery loop stays
/// under Android's undocumented scan-throttling threshold. Android can silently
/// return zero scan results once an app exceeds roughly five scan-start calls
/// within a rolling 30-second window on the same process; long scan windows
/// avoid repeatedly starting and stopping the scanner at that boundary.
///
/// This class only makes pacing decisions; it does not call any BLE API itself,
/// so it is fully unit-testable with an injected clock.
class ScanPacer {
  ScanPacer({
    this.maxStartsPerWindow = 5,
    this.throttleWindow = const Duration(seconds: 30),
    this.baseScanWindow = const Duration(seconds: 20),
    this.baseIdleWindow = const Duration(seconds: 2),
    this.maxScanWindow = const Duration(seconds: 20),
    this.maxIdleWindow = const Duration(seconds: 20),
    this.blindCyclesBeforeBackoff = 2,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// How many scan-start calls are allowed inside [throttleWindow] before
  /// [nextIdleDuration] defers a cycle rather than starting a scan Android is
  /// likely to silently drop.
  final int maxStartsPerWindow;
  final Duration throttleWindow;

  /// Cycle durations under normal (non-blind) operation. A long scan window
  /// is intentional: scan-start frequency, not scan duration, is the Android
  /// throttle trigger.
  final Duration baseScanWindow;
  final Duration baseIdleWindow;

  /// Ceilings applied once consecutive blind cycles trigger backoff.
  final Duration maxScanWindow;
  final Duration maxIdleWindow;

  /// Number of consecutive empty cycles tolerated before idle backoff starts.
  final int blindCyclesBeforeBackoff;

  final int Function() _nowMs;
  final List<int> _recentStartTimesMs = [];
  int _consecutiveBlindCycles = 0;

  bool get isThrottled {
    _pruneExpiredStarts();
    return _recentStartTimesMs.length >= maxStartsPerWindow;
  }

  /// Number of consecutive empty scan cycles currently recorded.
  int get consecutiveBlindCycles => _consecutiveBlindCycles;

  /// Records that a scan is about to start. Call immediately before invoking
  /// the platform scan API, once per attempt.
  void recordScanStart() {
    _pruneExpiredStarts();
    _recentStartTimesMs.add(_nowMs());
  }

  /// Records a completed scan. [peerExpected] prevents a transient empty
  /// window from beginning blind backoff while the caller has an active mesh
  /// candidate or connection attempt to keep servicing.
  void recordCycleResult({
    required int devicesSeen,
    bool peerExpected = false,
  }) {
    if (devicesSeen == 0 && !peerExpected) {
      _consecutiveBlindCycles++;
    } else {
      _consecutiveBlindCycles = 0;
    }
  }

  Duration nextIdleDuration() {
    if (isThrottled) return maxIdleWindow;
    if (_consecutiveBlindCycles < blindCyclesBeforeBackoff) {
      return baseIdleWindow;
    }
    final backoffSteps = _consecutiveBlindCycles - blindCyclesBeforeBackoff + 1;
    final scaledMs =
        baseIdleWindow.inMilliseconds * (1 << backoffSteps.clamp(0, 4));
    final capped = scaledMs.clamp(
      baseIdleWindow.inMilliseconds,
      maxIdleWindow.inMilliseconds,
    );
    return Duration(milliseconds: capped);
  }

  Duration nextScanWindow() =>
      baseScanWindow > maxScanWindow ? maxScanWindow : baseScanWindow;

  /// Approximate scan-on duty cycle for the next cycle, expressed as a whole
  /// percentage. This is a policy diagnostic, not a measurement of radio
  /// airtime.
  int dutyCyclePercent({Duration? idleWindow}) {
    final scan = nextScanWindow();
    final idle = idleWindow ?? nextIdleDuration();
    final cycleMs = scan.inMilliseconds + idle.inMilliseconds;
    if (cycleMs <= 0) return 0;
    return (scan.inMilliseconds * 100 / cycleMs).round();
  }

  void _pruneExpiredStarts() {
    final cutoff = _nowMs() - throttleWindow.inMilliseconds;
    // A start exactly at the rolling-window boundary is expired and must not
    // count toward the next window.
    _recentStartTimesMs.removeWhere((t) => t <= cutoff);
  }
}
