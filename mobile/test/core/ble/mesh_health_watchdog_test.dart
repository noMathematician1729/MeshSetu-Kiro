import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/core/ble/mesh_health_watchdog.dart';

void main() {
  test('a healthy cycle (devices seen and a connected peer) resets state', () {
    final watchdog = MeshHealthWatchdog();
    for (var i = 0; i < 5; i++) {
      watchdog.recordCycle(devicesSeen: 0, connectedPeerCount: 0);
    }
    expect(watchdog.consecutiveUnhealthyCycles, greaterThan(0));

    final action = watchdog.recordCycle(
      devicesSeen: 1,
      connectedPeerCount: 1,
    );
    expect(action, MeshHealthAction.none);
    expect(watchdog.consecutiveUnhealthyCycles, 0);
  });

  test('stays none until cyclesBeforeReassert unhealthy cycles have passed', () {
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
  });

  test('devices seen but never connecting also counts as unhealthy', () {
    final watchdog = MeshHealthWatchdog(cyclesBeforeReassert: 2);
    watchdog.recordCycle(devicesSeen: 3, connectedPeerCount: 0);
    final action = watchdog.recordCycle(devicesSeen: 3, connectedPeerCount: 0);
    expect(action, MeshHealthAction.reassertAdvertising);
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

  test('escalates to restartController after repeated failed reasserts', () {
    final watchdog = MeshHealthWatchdog(
      cyclesBeforeReassert: 1,
      cyclesBetweenReasserts: 1,
      reassertsBeforeRestart: 2,
    );
    final actions = <MeshHealthAction>[];
    for (var i = 0; i < 6; i++) {
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
  });

  test(
    'after a restart recommendation, a fresh unhealthy run gets its own grace period',
    () {
      final watchdog = MeshHealthWatchdog(
        cyclesBeforeReassert: 1,
        cyclesBetweenReasserts: 1,
        reassertsBeforeRestart: 1,
      );
      // Drive to restartController.
      MeshHealthAction? last;
      for (var i = 0; i < 3; i++) {
        last = watchdog.recordCycle(devicesSeen: 0, connectedPeerCount: 0);
      }
      expect(last, MeshHealthAction.restartController);

      // The next unhealthy cycle starts a fresh run, not an immediate
      // second restart.
      final next = watchdog.recordCycle(
        devicesSeen: 0,
        connectedPeerCount: 0,
      );
      expect(next, MeshHealthAction.reassertAdvertising);
    },
  );
}
