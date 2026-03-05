import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:frontend/main.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Clear preferences to ensure we start unauthenticated
    SharedPreferences.setMockInitialValues({});
  });

  group('end-to-end test', () {
    testWidgets('login and navigation flow', (tester) async {
      // Create a MockClient that fakes the necessary API responses
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/guest') {
          // Fake user response
          return http.Response(jsonEncode({
            'id': 1,
            'username': 'guest123',
            'is_guest': true,
          }), 200);
        } else if (request.url.path == '/api/v1/events') {
          // Fake empty events list
          return http.Response(jsonEncode([]), 200);
        }
        return http.Response('Not Found', 404);
      });

      // Override the apiClientProvider to use the mock
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith((ref) {
              final config = ref.watch(configServiceProvider);
              return ApiClient(config, client: mockClient);
            }),
          ],
          child: const MyApp(),
        ),
      );

      // Verify we start on the Login screen
      await tester.pumpAndSettle();
      expect(find.text('Welcome to ymatch'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);

      // Tap the Start button to log in
      await tester.tap(find.text('Start'));

      // Wait for network requests, navigation, and rendering to complete
      await tester.pumpAndSettle(const Duration(seconds: 1)); // Give some time for async flows

      // Verify we navigated to the Home screen (Events list)
      expect(find.text('Events'), findsWidgets); // AppBar title
      expect(find.text('No events found'), findsOneWidget); // Empty events state
    });
  });
}
