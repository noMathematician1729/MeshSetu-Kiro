import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/app/mesh_bridge_client.dart';
import 'package:meshsetu_mobile/app/providers.dart';
import 'package:meshsetu_mobile/core/data/database.dart';
import 'package:meshsetu_mobile/feature/onboarding/onboarding_profile.dart';
import 'package:meshsetu_mobile/feature/onboarding/onboarding_repository.dart';
import 'package:meshsetu_mobile/feature/rooms/room_chat_screen.dart';

OnboardingProfile _profile() => OnboardingProfile.create(
  profileId: 'profile-1',
  name: 'Asha',
  phone: '+919876543210',
  language: 'English',
  emergencyContacts: const [
    EmergencyContact(name: 'Ravi', phone: '+919876543211'),
  ],
  medicalProfile: const MedicalProfile(),
);

Future<OnboardingRepository> _onboardingRepository() async {
  final repository = OnboardingRepository(MemoryOnboardingStorage());
  await repository.save(_profile());
  return repository;
}

Widget _roomApp(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(
    home: RoomChatScreen(
      siteId: 'site',
      roomId: 'public',
      roomName: 'Public Alerts',
      role: 'public',
    ),
  ),
);

void main() {
  testWidgets(
    'offline room chat queues a durable GATT message and does not present cloud failure as room failure',
    (tester) async {
      final database = MeshDatabase.forTesting(NativeDatabase.memory());
      final onboarding = await _onboardingRepository();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          onboardingRepositoryProvider.overrideWithValue(onboarding),
          meshStatusProvider.overrideWith(
            (ref) => Stream.value(MeshStatus.stopped),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(database.close);
      container.read(gatewayEnabledProvider.notifier).state = false;

      await tester.pumpWidget(_roomApp(container));
      await tester.pump();

      expect(
        find.text('Event mode is off — messages will queue.'),
        findsOneWidget,
      );
      expect(find.text('Cloud: disabled'), findsOneWidget);
      expect(find.textContaining('Connection failed'), findsNothing);

      await tester.enterText(find.byType(TextField), 'offline GATT message');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final rows = await database.select(database.outboxEvents).get();
      final message = rows.singleWhere(
        (row) => row.payloadType == 'roomMessage',
      );
      expect(message.state, 'ready');
      expect(message.rawText, 'offline GATT message');
      expect(find.text('offline GATT message'), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
    },
  );

  testWidgets('room chat prioritizes connected mesh peers over cloud status',
      (tester) async {
    final database = MeshDatabase.forTesting(NativeDatabase.memory());
    final onboarding = await _onboardingRepository();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        onboardingRepositoryProvider.overrideWithValue(onboarding),
        meshStatusProvider.overrideWith(
          (ref) => Stream.value(
            const MeshStatus(
              eventModeRunning: true,
              peerCount: 2,
              statusText: 'advertising',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);
    container.read(gatewayEnabledProvider.notifier).state = false;

    await tester.pumpWidget(_roomApp(container));
    await tester.pump();

    expect(find.text('Mesh: 2 peers'), findsOneWidget);
    expect(find.byIcon(Icons.bluetooth_connected), findsOneWidget);
    expect(find.text('Cloud: disabled'), findsOneWidget);
    expect(
      find.text('Event mode is off — messages will queue.'),
      findsNothing,
    );
  });
}
