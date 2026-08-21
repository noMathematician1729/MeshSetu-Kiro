import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/database.dart';
import '../feature/join/join_repository.dart';
import '../feature/gateway/gateway_bridge.dart';
import '../feature/onboarding/onboarding_profile.dart';
import '../feature/onboarding/onboarding_repository.dart';
import '../feature/rooms/room_repository.dart';
import '../feature/rooms/room_presence.dart';
import '../feature/rooms/room_policy.dart';
import '../feature/sos/sos_repository.dart';
import '../feature/stt/sherpa_onnx_stt_engine.dart';
import '../feature/stt/stt_engine.dart';
import '../feature/voice/voice_repository.dart';
import 'mesh_bridge_client.dart';

/// Application-boundary Riverpod bindings (Bible §4.2): feature screens
/// depend on these repositories, never directly on `core/ble`/`core/data`.
final databaseProvider = Provider<MeshDatabase>((ref) {
  final db = MeshDatabase();
  ref.onDispose(db.close);
  return db;
});

final joinRepositoryProvider = Provider<JoinRepository>(
  (ref) => JoinRepository(ref.watch(databaseProvider)),
);

/// The currently joined site manifest, refreshed after `activateManifest`.
final activeSiteProvider = FutureProvider((ref) {
  ref.watch(_joinRefreshProvider);
  return ref.watch(joinRepositoryProvider).activeManifest();
});

/// Bumped by the join screen after a successful join to invalidate
/// [activeSiteProvider] without a manual `ref.invalidate` import cycle.
final _joinRefreshProvider = StateProvider((ref) => 0);

void refreshActiveSite(WidgetRef ref) =>
    ref.read(_joinRefreshProvider.notifier).state++;

/// Demo role selection — a real deployment derives this from the signed
/// manifest/authentication, not a local toggle.
final userRolesProvider = StateProvider<Set<String>>((ref) => const {'public'});

final roomRepositoryProvider = Provider.family<RoomRepository, String>(
  (ref, siteId) => RoomRepository(ref.watch(databaseProvider), siteId: siteId),
);

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(
    null,
    null,
    () {
      final url = ref.read(gatewayUrlProvider);
      final key = ref.read(gatewayDemoKeyProvider);
      final enabled = ref.read(gatewayEnabledProvider);
      if (!enabled || url.isEmpty || key.isEmpty) return null;
      return GatewayBridge(baseUrl: Uri.parse(url), demoKey: key);
    },
  );
});

final onboardingProfileProvider = FutureProvider<OnboardingProfile?>((ref) {
  return ref.watch(onboardingRepositoryProvider).load();
});

final sosRepositoryProvider = Provider<SosRepository>(
  (ref) => DriftSosRepository(
    ref.watch(databaseProvider),
    ref.watch(onboardingRepositoryProvider),
  ),
);

/// Real offline STT binding. A failed model load is reported to the SOS flow;
/// emergency packets never contain fabricated transcript text.
final offlineSttEngineProvider = Provider<OfflineSttEngine>(
  (ref) => SherpaOnnxEnglishSttEngine(),
);

/// Default Render deployment used by the event gateway. This can still be
/// overridden from the Gateway screen for local development or another site.
const productionBackendUrl = 'https://sih26-1xdevs.onrender.com';

final gatewayUrlProvider = StateProvider<String>((ref) => productionBackendUrl);
final gatewayEnabledProvider = StateProvider<bool>((ref) => true);
final gatewayDemoKeyProvider = StateProvider<String>((ref) => 'change-me');

final voiceRepositoryProvider = Provider<VoiceRepository>(
  (ref) => VoiceRepository(
    ref.watch(databaseProvider),
    ref.watch(sosRepositoryProvider),
  ),
);

final roomMessagesProvider = StreamProvider.family
    .autoDispose<
      List<RoomMessage>,
      ({String siteId, String roomId, String role, Set<String> userRoles})
    >(
      (ref, key) => ref
          .watch(roomRepositoryProvider(key.siteId))
          .watch(
            policy: policyForRole(key.roomId, key.role),
            userRoles: key.userRoles,
          ),
    );

final roomMembersProvider = StreamProvider.family
    .autoDispose<List<RoomMember>, ({String siteId, String roomId})>(
      (ref, key) => ref
          .watch(roomRepositoryProvider(key.siteId))
          .watchMembers(key.roomId),
    );

/// The live [MeshBridgeClient] owned by the event-mode screen, published
/// here so other screens (room chat/lobby) can observe mesh connectivity
/// without a direct reference to the widget that owns the foreground
/// service connection. Null when event mode has never started or has been
/// torn down.
final meshBridgeClientProvider = StateProvider<MeshBridgeClient?>(
  (ref) => null,
);

/// Mesh-first connectivity status for room screens: peer count and whether
/// the foreground BLE service is running, independent of the internet
/// [RoomPresenceSocket]. Falls back to [MeshStatus.stopped] whenever no
/// bridge client is registered yet.
final meshStatusProvider = StreamProvider<MeshStatus>((ref) {
  final client = ref.watch(meshBridgeClientProvider);
  if (client == null) return Stream.value(MeshStatus.stopped);
  return Stream.multi((controller) {
    controller.add(client.meshStatus);
    final subscription = client.meshStatusStream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  });
});
