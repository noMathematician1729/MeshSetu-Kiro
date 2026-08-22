import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/mesh_health_watchdog.dart';

class _FakeClock {
  int nowMs = 0;
  int call() => nowMs;
}

void main() {
  test('a healthy cycle (devices seen and a connected peer) resets state', () {
    final watchdog = MeshHealthWatchdog();
    for (var i = 0; i < 5; i++) {
      watchdog.recordCycle(devicesSeen: 0, connectedPeerCount: 0);
    }
    expect(watchdog.consecutiveUnhealthyCycles, greaterThan(0));

    final action = watchdog.recordCycle(devicesSeen: 1, connectedPeerCount: 1);
    expect(action, MeshHealthAction.none);
    expect(watchdog.consecutiveUnhealthyCycles, 0);
  });

  test(
    'stays none until cyclesBeforeReassert unhealthy cycles have passed',
    () {
      final watchdog = MeshHealthWatchdog(cyclesBeforeReassert: 3);
      expect(
        watchdog.recordCycle(devicesSeen: 0, connectedPeerCount: 0),
        MeshHealthAction.none,
      );
      expect(
        watchdog.recordCycle(devicesSeen: 0, connectedPeerCount: 0),
        MeshHealthAction.none,
      );
      expect(
        watchdog.recordCycle(devicesSeen: 0, connectedPeerCount: 0),
        MeshHealthAction.reassertAdvertising,
      );
    },
  );

  test('visible devices with no connected peers are not unhealthy', () {
    final watchdog = MeshHealthWatchdog(cyclesBeforeReassert: 1);
    for (var i = 0; i < 20; i++) {
      expect(
        watchdog.recordCycle(devicesSeen: 3, connectedPeerCount: 0),
        MeshHealthAction.none,
      );
    }
    expect(watchdog.consecutiveUnhealthyCycles, 0);
  });

  test('does not recommend another reassert before cyclesBetweenReasserts', () {
    final watchdog = MeshHealthWatchdog(
      cyclesBeforeReassert: 1,
      cyclesBetweenReasserts: 3,
    );
    expect(
      watchdog.recordCycle(devicesSeen: 0, connectedPeerCount: 0),
      MeshHealthAction.reassertAdvertising,
    );
    expect(
      watchdog.recordCycle(devicesSeen: 0, connectedPeerCount: 0),
      MeshHealthAction.none,
    );
    expect(
      watchdog.recordCycle(devicesSeen: 0, connectedPeerCount: 0),
      MeshHealthAction.none,
    );
    expect(
      watchdog.recordCycle(devicesSeen: 0, connectedPeerCount: 0),
      MeshHealthAction.none,
    );
    expect(
      watchdog.recordCycle(devicesSeen: 0, connectedPeerCount: 0),
      MeshHealthAction.reassertAdvertising,
    );
  });

  test(
    'sustained blind cycles can escalate only after restart guards pass',
    () {
      final clock = _FakeClock();
      final watchdog = MeshHealthWatchdog(
        cyclesBeforeReassert: 1,
        cyclesBetweenReasserts: 1,
        reassertsBeforeRestart: 2,
        minimumCyclesBeforeRestart: 4,
        minimumRestartAge: const Duration(seconds: 10),
        maxRestartsPerSession: 1,
        nowMs: clock.call,
      );
      final actions = <MeshHealthAction>[];
      for (var i = 0; i < 7; i++) {
        clock.nowMs += const Duration(seconds: 2).inMilliseconds;
        actions.add(
          watchdog.recordCycle(devicesSeen: 0, connectedPeerCount: 0),
        );
      }
      expect(
        actions,
        containsAllInOrder([
          MeshHealthAction.reassertAdvertising,
          MeshHealthAction.reassertAdvertising,
          MeshHealthAction.restartController,
        ]),
      );
      expect(watchdog.restartsThisSession, 1);
    },
  );

  test('default restart policy is delayed for a lone blind session', () {
    final clock = _FakeClock();
    final watchdog = MeshHealthWatchdog(
      cyclesBeforeReassert: 1,
      cyclesBetweenReasserts: 1,
      reassertsBeforeRestart: 1,
      nowMs: clock.call,
    );
    for (var i = 0; i < 10; i++) {
      clock.nowMs += const Duration(seconds: 5).inMilliseconds;
      expect(
        watchdog.recordCycle(devicesSeen: 0, connectedPeerCount: 0),
        isNot(MeshHealthAction.restartController),
      );
    }
    expect(watchdog.restartsThisSession, 0);
  });

  test('restart budget is capped for one watchdog session', () {
    final clock = _FakeClock();
    final watchdog = MeshHealthWatchdog(
      cyclesBeforeReassert: 1,
      cyclesBetweenReasserts: 1,
      reassertsBeforeRestart: 0,
      minimumCyclesBeforeRestart: 1,
      minimumRestartAge: Duration.zero,
      maxRestartsPerSession: 1,
      nowMs: clock.call,
    );
    expect(
      watchdog.recordCycle(devicesSeen: 0, connectedPeerCount: 0),
      MeshHealthAction.restartController,
    );
    for (var i = 0; i < 5; i++) {
      expect(
        watchdog.recordCycle(devicesSeen: 0, connectedPeerCount: 0),
        isNot(MeshHealthAction.restartController),
      );
    }
    expect(watchdog.restartsThisSession, 1);
  });
}
