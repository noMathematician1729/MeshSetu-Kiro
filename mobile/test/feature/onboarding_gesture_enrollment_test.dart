import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/app/providers.dart';
import 'package:meshsetu_mobile/feature/onboarding/onboarding_repository.dart';
import 'package:meshsetu_mobile/feature/onboarding/onboarding_screen.dart';

void main() {
  const gestureChannel = MethodChannel('meshsetu/emergency-gestures');

  testWidgets('initial Android onboarding requires emergency gestures', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(gestureChannel, (call) async {
      if (call.method == 'isEnabled') return false;
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(gestureChannel, null);
    });

    final storage = MemoryOnboardingStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingRepositoryProvider.overrideWithValue(
            OnboardingRepository(storage),
          ),
        ],
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
    await tester.pump();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Asha Patel');
    await tester.enterText(fields.at(1), '+919876543210');
    await tester.enterText(fields.at(2), 'English');
    await tester.enterText(fields.at(3), 'Ravi Patel');
    await tester.enterText(fields.at(4), '+919876543211');
    final save = find.text('Save emergency profile');
    await tester.scrollUntilVisible(
      save,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pump();

    expect(find.textContaining('Enable Emergency gestures'), findsOneWidget);
    expect(storage.value, isNull);
  });
}
