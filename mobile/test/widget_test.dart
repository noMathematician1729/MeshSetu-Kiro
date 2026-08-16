import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshsetu_mobile/main.dart';

void main() {
  testWidgets('shows event mode off status and start button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MeshSetuApp(enforcePermissions: false)),
    );

    expect(find.textContaining('Event mode is off'), findsOneWidget);
    expect(find.text('Start event mode'), findsOneWidget);
  });
}
