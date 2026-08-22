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
  /// Restart the whole [MeshEventController] (stop then start) — this is
  /// disruptive (drops connected peers, who must rediscover and reconnect)
  /// so it is reserved for genuinely stuck radios, matching the "stop and
  /// restart Event Mode" workaround this whole plan exists to make
  /// unnecessary.
  restartController,
}

/// Detects a mesh radio that is blind or peer-accept-starved for an
/// extended run of scan cycles and recommends an escalating recovery action
/// (Bible audit Task 9) — the self-healing counterpart to [ScanPacer]'s
/// throttle-safe pacing. Without this, the only recovery from a wedged
/// radio is the user manually stopping and restarting Event Mode.
///
/// Pure decision logic with no BLE/timer access, matching [ScanPacer]'s
/// split of policy from I/O so recovery timing is directly unit-testable.
class MeshHealthWatchdog {
  MeshHealthWatchdog({
    this.cyclesBeforeReassert = 3,
    this.reassertsBeforeRestart = 2,
    this.cyclesBetweenReasserts = 3,
  });

  /// Consecutive unhealthy cycles (see [recordCycle]) before the first
  /// [MeshHealthAction.reassertAdvertising] recommendation.
  final int cyclesBeforeReassert;

  /// How many [MeshHealthAction.reassertAdvertising] recommendations can
  /// pass without recovery before escalating to
  /// [MeshHealthAction.restartController].
  final int reassertsBeforeRestart;

  /// Minimum unhealthy cycles between one reassert recommendation and the
  /// next, so the watchdog does not recommend a reassert on every single
  /// cycle while waiting to see if the previous one worked.
  final int cyclesBetweenReasserts;

  int _consecutiveUnhealthyCycles = 0;
  int? _cyclesSinceLastReassert;
  int _reassertsSinceHealthy = 0;

  /// Cycles since the current unhealthy run started, for observability
  /// (e.g. attaching to a `mesh_health_action` metric's detail).
  int get consecutiveUnhealthyCycles => _consecutiveUnhealthyCycles;

  /// Records one scan cycle's outcome and returns the recommended action.
  ///
  /// A cycle is unhealthy when [devicesSeen] is zero (nobody visible at
  /// all — matches [ScanPacer]'s blind-cycle signal) or when devices were
  /// seen but [connectedPeerCount] stayed at zero for
  /// [cyclesBeforeReassert] cycles running (visible peers that never
  /// resolve into a connection — the exact one-sided-ownership symptom
  /// Task 6 targets, kept here as a second line of defense).
  MeshHealthAction recordCycle({
    required int devicesSeen,
    required int connectedPeerCount,
  }) {
    final healthy = devicesSeen > 0 && connectedPeerCount > 0;
    if (healthy) {
      _consecutiveUnhealthyCycles = 0;
      _cyclesSinceLastReassert = null;
      _reassertsSinceHealthy = 0;
      return MeshHealthAction.none;
    }

    _consecutiveUnhealthyCycles++;
    final sinceLastReassert = _cyclesSinceLastReassert;
    if (sinceLastReassert != null) _cyclesSinceLastReassert = sinceLastReassert + 1;
    if (_consecutiveUnhealthyCycles < cyclesBeforeReassert) {
      return MeshHealthAction.none;
    }
    // The first reassert of a run only waits for cyclesBeforeReassert.
    // Subsequent ones additionally wait cyclesBetweenReasserts after the
    // previous one, so the watchdog does not recommend a reassert on every
    // cycle while waiting to see if the last one worked.
    if (sinceLastReassert != null && sinceLastReassert < cyclesBetweenReasserts) {
      return MeshHealthAction.none;
    }

    _cyclesSinceLastReassert = 0;
    _reassertsSinceHealthy++;
    if (_reassertsSinceHealthy > reassertsBeforeRestart) {
      // Restarting is the terminal action for one unhealthy run: reset so
      // a fresh run after the restart gets its own full grace period
      // rather than immediately escalating again.
      _consecutiveUnhealthyCycles = 0;
      _cyclesSinceLastReassert = null;
      _reassertsSinceHealthy = 0;
      return MeshHealthAction.restartController;
    }
    return MeshHealthAction.reassertAdvertising;
  }
}
