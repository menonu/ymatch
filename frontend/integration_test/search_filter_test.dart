import 'package:flutter/material.dart';
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
    SharedPreferences.setMockInitialValues({});
  });

  group('Search and Filter E2E Test', () {
    testWidgets(
      'Verify search and filtering on Home and Event Detail screens',
      (tester) async {
        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/v1/auth/guest') {
            return http.Response(
              jsonEncode({'id': 1, 'username': 'testuser', 'is_guest': true}),
              200,
            );
          } else if (request.url.path == '/api/v1/events') {
            return http.Response(
              jsonEncode([
                {
                  'id': 1,
                  'name': 'Flutter Event',
                  'isFavorite': true,
                  'isJoined': false,
                  'createdAt': DateTime.now().toIso8601String(),
                },
                {
                  'id': 2,
                  'name': 'Rust Event',
                  'isFavorite': false,
                  'isJoined': true,
                  'createdAt': DateTime.now().toIso8601String(),
                },
              ]),
              200,
            );
          } else if (request.url.path == '/api/v1/events/1/merch') {
            return http.Response(
              jsonEncode([
                {'id': 1, 'eventId': 1, 'name': 'Sticker', 'groupName': 'Swag'},
                {'id': 2, 'eventId': 1, 'name': 'T-Shirt', 'groupName': 'Swag'},
              ]),
              200,
            );
          } else if (request.url.path == '/api/v1/user/1/inventory') {
            return http.Response(
              jsonEncode([
                {
                  'id': 101,
                  'userId': 1,
                  'merchId': 1,
                  'status': 'HAVE',
                  'quantity': 1,
                  'merchName': 'Sticker',
                },
              ]),
              200,
            );
          } else if (request.url.path.contains('/favorite_groups')) {
            return http.Response(jsonEncode([]), 200);
          } else if (request.url.path.contains('/view')) {
            return http.Response(jsonEncode({}), 200);
          }
          return http.Response('Not Found', 404);
        });

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

        await tester.pumpAndSettle();

        // Login
        await tester.tap(find.text('Start'));
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // 1. Home Screen Verification
        expect(find.text('Flutter Event'), findsOneWidget);
        expect(find.text('Rust Event'), findsOneWidget);

        // Search
        final homeSearch = find.byType(SearchBar).first;
        await tester.enterText(homeSearch, 'Flutter');
        await tester.pumpAndSettle();
        expect(find.text('Flutter Event'), findsOneWidget);
        expect(find.text('Rust Event'), findsNothing);

        // Clear search
        await tester.tap(find.byIcon(Icons.clear));
        await tester.pumpAndSettle();
        expect(find.text('Flutter Event'), findsOneWidget);
        expect(find.text('Rust Event'), findsOneWidget);

        // Filter: Favorites
        await tester.tap(find.text('Favorites'));
        await tester.pumpAndSettle();
        expect(find.text('Flutter Event'), findsOneWidget);
        expect(find.text('Rust Event'), findsNothing);

        // Filter: My Items
        await tester.tap(find.text('My Items'));
        await tester.pumpAndSettle();
        expect(find.text('Rust Event'), findsOneWidget);
        expect(find.text('Flutter Event'), findsNothing);

        // Back to All
        await tester.tap(find.text('All Events'));
        await tester.pumpAndSettle();

        // 2. Event Detail Screen Verification
        await tester.tap(find.text('Flutter Event'));
        await tester.pumpAndSettle(const Duration(seconds: 1));

        expect(find.text('Sticker'), findsOneWidget);
        expect(find.text('T-Shirt'), findsOneWidget);

        // Search Items
        final detailSearch = find.byType(SearchBar).first;
        await tester.enterText(detailSearch, 'Sticker');
        await tester.pumpAndSettle();
        expect(find.text('Sticker'), findsOneWidget);
        expect(find.text('T-Shirt'), findsNothing);

        // Clear Search
        await tester.tap(find.byIcon(Icons.clear));
        await tester.pumpAndSettle();

        // Inventory Filter: Just HAVE
        await tester.tap(find.text('Just HAVE'));
        await tester.pumpAndSettle();
        expect(find.text('HAVE'), findsWidgets);
        expect(find.text('WANT'), findsNothing);

        // Inventory Filter: WANT & TRADE
        await tester.tap(find.text('WANT & TRADE'));
        await tester.pumpAndSettle();
        expect(find.text('HAVE'), findsNothing);
        expect(find.text('WANT'), findsWidgets);
        expect(find.text('TRADE'), findsWidgets);
      },
    );
  });
}
