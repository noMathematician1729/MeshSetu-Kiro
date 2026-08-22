import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_mode_launcher.dart';
import 'mesh_bridge_client.dart';
import 'providers.dart';

/// Binds a room's joined site to the foreground BLE task and its UI-isolate
/// outbox bridge. This is intentionally shared by the lobby and chat screens:
/// participants may enter either screen without first visiting Event Mode.
abstract final class RoomMeshBootstrap {
  static Future<EventModeLaunchResult> startForSite({
    required WidgetRef ref,
    required String siteId,
    required void Function() taskCallback,
  }) async {
    await EventModeLauncher.initialize();
    final bridge = _ensureBridge(ref);
    bridge.prepareForSite(siteId: siteId);

    final result = await EventModeLauncher.start(
      taskCallback: taskCallback,
      onStatus: bridge.reportBlockedReason,
      onMeshSiteConfigurationNeeded: () =>
          EventModeLauncher.configureMeshSite(siteId),
    );

    if (result == EventModeLaunchResult.alreadyRunning) {
      // EventModeLauncher intentionally does not invoke its configuration
      // callback on this fast path. Configure the already-running task and
      // ask it to return its identity to this newly attached bridge.
      await EventModeLauncher.configureMeshSite(siteId);
      _requestIdentityWithRetry(bridge);
    } else if (result == EventModeLaunchResult.started) {
      // The service request can complete before its task isolate has created
      // the controller. Replay the identity request after startup as a
      // safeguard for the first-start callback race.
      _requestIdentityWithRetry(bridge);
    }
    return result;
  }

  static void _requestIdentityWithRetry(MeshBridgeClient bridge) {
    unawaited(() async {
      for (final delay in const [
        Duration.zero,
        Duration(milliseconds: 500),
        Duration(seconds: 2),
      ]) {
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        bridge.requestForegroundIdentity();
      }
    }());
  }

  static MeshBridgeClient _ensureBridge(WidgetRef ref) {
    final existing = ref.read(meshBridgeClientProvider);
    if (existing != null) return existing;
    final bridge = MeshBridgeClient(ref.read(databaseProvider));
    ref.read(meshBridgeClientProvider.notifier).state = bridge;
    return bridge;
  }
}
