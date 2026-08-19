import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/database.dart';
import '../feature/join/join_repository.dart';
import '../feature/gateway/gateway_bridge.dart';
import '../feature/onboarding/onboarding_profile.dart';
import '../feature/onboarding/onboarding_repository.dart';
import '../feature/rooms/room_repository.dart';
import '../feature/sos/sos_repository.dart';
import '../feature/stt/sherpa_onnx_stt_engine.dart';
import '../feature/stt/stt_engine.dart';
import '../feature/voice/voice_repository.dart';

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
  final url = ref.watch(gatewayUrlProvider);
  final key = ref.watch(gatewayDemoKeyProvider);
  final enabled = ref.watch(gatewayEnabledProvider);
  final bridge = (enabled && url.isNotEmpty && key.isNotEmpty)
      ? GatewayBridge(baseUrl: Uri.parse(url), demoKey: key)
      : null;
  return OnboardingRepository(null, bridge);
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
    .autoDispose<List<RoomMessage>, ({String siteId, String roomId})>(
      (ref, key) =>
          ref.watch(roomRepositoryProvider(key.siteId)).watch(key.roomId),
    );
