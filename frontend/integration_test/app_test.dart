import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';
import 'package:frontend/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('end-to-end test', () {
    testWidgets('Guest login and navigate to events screen',
        (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Verify that the app starts and LoginScreen is shown.
      expect(find.text('Welcome to ymatch'), findsOneWidget);

      // Find the 'Start' button and tap it.
      final startButton = find.widgetWithText(ElevatedButton, 'Start');
      expect(startButton, findsOneWidget);
      await tester.tap(startButton);

      // Wait for login request and navigation.
      await tester.pumpAndSettle();

      // Verify that HomeScreen is shown.
      expect(find.text('Events'), findsOneWidget);
      expect(find.text('All Events'), findsOneWidget);
    });
  });
}
