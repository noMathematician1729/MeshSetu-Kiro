/// Escalating recovery action recommended by [MeshHealthWatchdog] for the
/// current run of unhealthy scan cycles.
enum MeshHealthAction {
  /// The mesh is healthy (or has not been unhealthy long enough to act) —
  /// no recovery step needed.
  none,

  /// First-line recovery: re-assert advertising ([MeshAdvertiser.reassert])
  /// and let the scan pacer's own backoff continue. Cheap and non-disruptive
  /// to any peers already connected.
  reassertAdvertising,

  /// Nothing has recovered after repeated [reassertAdvertising] escalations.
  /// Restart the whole [MeshEventController] (stop then start) — disruptive,
  /// so it is reserved for sustained radio blindness.
  restartController,
}

/// Detects a mesh radio that is blind for an extended run of scan cycles and
/// recommends an escalating recovery action (Bible audit Task 9).
///
/// A device that can see any BLE device is not radio-blind, even if it has no
/// attached mesh peer yet. This distinction is important: being alone,
/// waiting for the other side to connect, or completing GATT setup must not
/// tear down a healthy event-mode session. Controller restarts are additionally
/// delayed by both a cycle and wall-clock minimum and capped once per session.
///
/// Pure decision logic with no BLE/timer access, matching [ScanPacer]'s split
/// of policy from I/O so recovery timing is directly unit-testable.
class MeshHealthWatchdog {
  MeshHealthWatchdog({
    this.cyclesBeforeReassert = 3,
    this.reassertsBeforeRestart = 2,
    this.cyclesBetweenReasserts = 3,
    this.minimumCyclesBeforeRestart = 12,
    this.minimumRestartAge = const Duration(minutes: 2),
    this.maxRestartsPerSession = 1,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Consecutive blind cycles before the first
  /// [MeshHealthAction.reassertAdvertising] recommendation.
  final int cyclesBeforeReassert;

  /// How many [MeshHealthAction.reassertAdvertising] recommendations can
  /// pass without recovery before considering a controller restart.
  final int reassertsBeforeRestart;

  /// Minimum blind cycles between reassert recommendations.
  final int cyclesBetweenReasserts;

  /// Additional guard against restarting after a short-lived scan outage.
  final int minimumCyclesBeforeRestart;

  /// Wall-clock guard against rapid stop/start churn when scan cycles are
  /// shorter than expected or are delivered in a burst.
  final Duration minimumRestartAge;

  /// A controller instance may perform at most this many automated restarts.
  /// The counter is intentionally not reset by a healthy cycle; only a new
  /// controller instance gets a new recovery budget.
  final int maxRestartsPerSession;

  final int Function() _nowMs;
  int _consecutiveUnhealthyCycles = 0;
  int? _cyclesSinceLastReassert;
  int _reassertsSinceHealthy = 0;
  int? _unhealthySinceMs;
  int _restartsThisSession = 0;

  /// Cycles since the current blind run started, for observability.
  int get consecutiveUnhealthyCycles => _consecutiveUnhealthyCycles;

  /// Number of automated controller restarts already recommended in this
  /// watchdog session.
  int get restartsThisSession => _restartsThisSession;

  /// Records one scan cycle's outcome and returns the recommended action.
  ///
  /// Only [devicesSeen] determines radio blindness. [connectedPeerCount] is
  /// deliberately not part of the health predicate: a phone can be alone,
  /// waiting for a peer, or still completing GATT setup while its radio is
  /// demonstrably receiving advertisements from other devices.
  MeshHealthAction recordCycle({
    required int devicesSeen,
    required int connectedPeerCount,
  }) {
    // Keep the parameter in the public contract for call-site observability
    // and future policy, but never treat zero attached peers as radio failure.
    final healthy = devicesSeen > 0;
    if (healthy) {
      _consecutiveUnhealthyCycles = 0;
      _cyclesSinceLastReassert = null;
      _reassertsSinceHealthy = 0;
      _unhealthySinceMs = null;
      return MeshHealthAction.none;
    }

    final now = _nowMs();
    _unhealthySinceMs ??= now;
    _consecutiveUnhealthyCycles++;
    final sinceLastReassert = _cyclesSinceLastReassert;
    if (sinceLastReassert != null) {
      _cyclesSinceLastReassert = sinceLastReassert + 1;
    }
    if (_consecutiveUnhealthyCycles < cyclesBeforeReassert) {
      return MeshHealthAction.none;
    }
    // The first reassert waits for cyclesBeforeReassert. Subsequent ones
    // additionally wait cyclesBetweenReasserts.
    if (sinceLastReassert != null &&
        sinceLastReassert < cyclesBetweenReasserts) {
      return MeshHealthAction.none;
    }

    _cyclesSinceLastReassert = 0;
    _reassertsSinceHealthy++;
    if (_reassertsSinceHealthy <= reassertsBeforeRestart) {
      return MeshHealthAction.reassertAdvertising;
    }

    final restartAge = now - (_unhealthySinceMs ?? now);
    final restartAllowed =
        _restartsThisSession < maxRestartsPerSession &&
        _consecutiveUnhealthyCycles >= minimumCyclesBeforeRestart &&
        restartAge >= minimumRestartAge.inMilliseconds;
    if (!restartAllowed) return MeshHealthAction.none;

    _restartsThisSession++;
    // Reset the current run after recommending a restart. The controller will
    // normally be replaced; resetting here also makes the pure state machine
    // safe if a caller elects not to restart after observing the metric.
    _consecutiveUnhealthyCycles = 0;
    _cyclesSinceLastReassert = null;
    _reassertsSinceHealthy = 0;
    _unhealthySinceMs = null;
    return MeshHealthAction.restartController;
  }
}
