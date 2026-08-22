/// Paces repeated BLE scan starts so the long-running discovery loop stays
/// under Android's undocumented scan-throttling threshold (Bible audit
/// Task 2). Android silently returns zero scan results — with no error —
/// once an app exceeds roughly 5 scan-start calls within a rolling 30
/// second window on the same process; this is the top suspect for
/// discovery working one session and going silent the next, since the
/// throttle state persists per-app until the window ages out.
///
/// This class only makes pacing *decisions*; it does not call any BLE API
/// itself, so it is fully unit-testable with an injected clock.
class ScanPacer {
  ScanPacer({
    this.maxStartsPerWindow = 5,
    this.throttleWindow = const Duration(seconds: 30),
    this.baseScanWindow = const Duration(seconds: 4),
    this.baseIdleWindow = const Duration(seconds: 2),
    this.maxScanWindow = const Duration(seconds: 4),
    this.maxIdleWindow = const Duration(seconds: 20),
    this.blindCyclesBeforeBackoff = 2,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// How many scan-start calls are allowed inside [throttleWindow] before
  /// [nextIdleDuration] defers a cycle entirely rather than starting a scan
  /// Android is likely to silently drop.
  final int maxStartsPerWindow;
  final Duration throttleWindow;

  /// Cycle durations under normal (non-blind) operation.
  final Duration baseScanWindow;
  final Duration baseIdleWindow;

  /// Ceilings applied once consecutive blind cycles trigger backoff.
  final Duration maxScanWindow;
  final Duration maxIdleWindow;

  /// Number of consecutive "zero devices seen" cycles tolerated before the
  /// idle window starts lengthening. A single blind cycle is normal (no one
  /// nearby); repeated blind cycles combined with throttling risk are the
  /// signal worth backing off for.
  final int blindCyclesBeforeBackoff;

  final int Function() _nowMs;
  final List<int> _recentStartTimesMs = [];
  int _consecutiveBlindCycles = 0;

  /// Whether starting a scan right now would push this process over the
  /// rolling-window throttle threshold. Callers should defer instead of
  /// starting a scan Android is likely to silently drop.
  bool get isThrottled {
    _pruneExpiredStarts();
    return _recentStartTimesMs.length >= maxStartsPerWindow;
  }

  /// Records that a scan is about to start. Call this immediately before
  /// invoking the platform scan API, once per attempt — including attempts
  /// that end up deferred by the caller after checking [isThrottled], since
  /// the intent to scan is what Android's throttle counts against.
  void recordScanStart() {
    _pruneExpiredStarts();
    _recentStartTimesMs.add(_nowMs());
  }

  /// Records the outcome of a completed scan window so the next idle
  /// duration can adapt. [devicesSeen] is the raw BLE device count from
  /// `MeshScanReport.devicesSeen`, not just accepted mesh peers — a
  /// throttled scan reports zero devices seen at all, which is how this
  /// distinguishes "throttled/blind" from "peers simply not accepted".
  void recordCycleResult({required int devicesSeen}) {
    if (devicesSeen == 0) {
      _consecutiveBlindCycles++;
    } else {
      _consecutiveBlindCycles = 0;
    }
  }

  /// Duration to wait before the next scan-start attempt. Lengthens beyond
  /// [baseIdleWindow] once [blindCyclesBeforeBackoff] consecutive blind
  /// cycles have occurred, and lengthens further (up to [maxIdleWindow])
  /// whenever a scan start would currently be throttled — giving Android's
  /// rolling window time to age out instead of hammering a blocked radio.
  Duration nextIdleDuration() {
    if (isThrottled) return maxIdleWindow;
    if (_consecutiveBlindCycles < blindCyclesBeforeBackoff) {
      return baseIdleWindow;
    }
    final backoffSteps = _consecutiveBlindCycles - blindCyclesBeforeBackoff + 1;
    final scaledMs = baseIdleWindow.inMilliseconds * (1 << backoffSteps.clamp(0, 4));
    final capped = scaledMs.clamp(
      baseIdleWindow.inMilliseconds,
      maxIdleWindow.inMilliseconds,
    );
    return Duration(milliseconds: capped);
  }

  /// Duration to scan for once a scan is allowed to start. Currently fixed
  /// at [baseScanWindow] — window *length* is not the throttle trigger,
  /// start *frequency* is, so only [nextIdleDuration] adapts. Exposed as a
  /// method (not a constant getter) so future policy can vary it without
  /// changing the call site.
  Duration nextScanWindow() => baseScanWindow;

  void _pruneExpiredStarts() {
    final cutoff = _nowMs() - throttleWindow.inMilliseconds;
    _recentStartTimesMs.removeWhere((t) => t < cutoff);
  }
}
