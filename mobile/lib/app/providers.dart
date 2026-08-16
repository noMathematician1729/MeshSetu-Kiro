import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/database.dart';
import '../feature/join/join_repository.dart';
import '../feature/rooms/room_repository.dart';
import '../feature/sos/sos_repository.dart';
import '../feature/stt/fake_stt_engine.dart';
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

final sosRepositoryProvider = Provider<SosRepository>(
  (ref) => DriftSosRepository(ref.watch(databaseProvider)),
);

/// Dev-only STT binding. Replace this provider's implementation with the real
/// offline engine once model assets are present in `assets/models/`.
final offlineSttEngineProvider = Provider<OfflineSttEngine>(
  (ref) => _FallbackOfflineSttEngine(
    primary: SherpaOnnxEnglishSttEngine(),
    fallback: const FakeOfflineSttEngine(),
  ),
);

final gatewayUrlProvider = StateProvider<String>((ref) => '');
final gatewayEnabledProvider = StateProvider<bool>((ref) => false);
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

final class _FallbackOfflineSttEngine implements OfflineSttEngine {
  _FallbackOfflineSttEngine({required this.primary, required this.fallback});

  final OfflineSttEngine primary;
  final OfflineSttEngine fallback;

  OfflineSttEngine? _selected;
  Object? _primaryError;

  @override
  Future<void> warmUp() async {
    if (_selected != null) {
      await _selected!.warmUp();
      return;
    }
    try {
      await primary.warmUp();
      _selected = primary;
      _primaryError = null;
    } catch (error) {
      _primaryError = error;
      await fallback.warmUp();
      _selected = fallback;
    }
  }

  @override
  Future<SttResult> transcribe(Uint8List pcm16le, {int sampleRateHz = 16000}) async {
    await warmUp();
    final result = await _selected!.transcribe(
      pcm16le,
      sampleRateHz: sampleRateHz,
    );
    if (!identical(_selected, fallback)) return result;
    final reason = _primaryError?.toString() ?? 'unknown error';
    return SttResult(
      text: result.text,
      confidence: result.confidence,
      inferenceMs: result.inferenceMs,
      modelId: '${result.modelId} [fallback: $reason]',
    );
  }

  @override
  Future<void> close() async {
    await primary.close();
    await fallback.close();
    _selected = null;
    _primaryError = null;
  }
}
