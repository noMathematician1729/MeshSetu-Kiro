import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meshsetu_mobile/app/providers.dart';
import 'package:meshsetu_mobile/feature/gateway/gateway_bridge.dart';
import 'package:meshsetu_mobile/feature/onboarding/onboarding_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'gateway url change must not invalidate onboardingProfileProvider',
    () async {
      final container = ProviderContainer(
        overrides: [
          onboardingRepositoryProvider.overrideWith((ref) {
            return OnboardingRepository(
              MemoryOnboardingStorage(),
              null,
              () {
                final url = ref.read(gatewayUrlProvider);
                final key = ref.read(gatewayDemoKeyProvider);
                final enabled = ref.read(gatewayEnabledProvider);
                if (!enabled || url.isEmpty || key.isEmpty) return null;
                return GatewayBridge(
                  baseUrl: Uri.parse(url),
                  demoKey: key,
                );
              },
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(onboardingProfileProvider.future);

      container.read(gatewayUrlProvider.notifier).state =
          'https://example.test/a';

      final after = container.read(onboardingProfileProvider);

      expect(
        after.isLoading,
        isFalse,
        reason: 'typing gateway URL must not put onboarding gate into loading',
      );
    },
  );
}
