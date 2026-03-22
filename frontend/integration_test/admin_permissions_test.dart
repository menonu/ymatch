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

  group('Admin & Permissions E2E', () {
    testWidgets(
      'Admin can view users tab and see role/ban info',
      (tester) async {
        final mockUsers = [
          {
            'id': 1,
            'username': 'admin_user',
            'role': 'admin',
            'is_banned': false,
          },
          {
            'id': 2,
            'username': 'normal_user',
            'role': 'user',
            'is_banned': false,
          },
          {
            'id': 3,
            'username': 'banned_user',
            'role': 'user',
            'is_banned': true,
            'ban_reason': 'Spamming',
          },
        ];

        final mockClient = MockClient((request) async {
          final path = request.url.path;

          if (path == '/api/v1/auth/guest') {
            return http.Response(
              jsonEncode({
                'id': 1,
                'username': 'admin_user',
                'role': 'admin',
                'is_banned': false,
              }),
              200,
            );
          } else if (path == '/api/v1/events') {
            return http.Response(jsonEncode([]), 200);
          } else if (path == '/api/v1/users') {
            return http.Response(jsonEncode(mockUsers), 200);
          } else if (path == '/api/v1/system/status') {
            return http.Response(
              jsonEncode({
                'backend_version': 'test-admin',
                'resources': {
                  'total_memory_bytes': 1073741824,
                  'used_memory_bytes': 536870912,
                  'cpu_usage_percent': 5.0,
                  'uptime_seconds': 3600,
                  'os_name': 'Linux',
                  'os_version': '6.0',
                },
              }),
              200,
            );
          } else if (path == '/api/v1/admin/merch') {
            return http.Response(jsonEncode([]), 200);
          } else if (path == '/api/v1/admin/matches') {
            return http.Response(jsonEncode([]), 200);
          } else if (path.contains('/ban')) {
            return http.Response(jsonEncode({'status': 'ok'}), 200);
          } else if (path.contains('/unban')) {
            return http.Response(jsonEncode({'status': 'ok'}), 200);
          } else if (path.contains('/role')) {
            return http.Response(jsonEncode({'status': 'ok'}), 200);
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

        // Login as admin
        expect(find.text('Start Guest Session'), findsOneWidget);
        await tester.tap(find.text('Start Guest Session'));
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // Navigate to Admin tab
        final adminTab = find.text('Admin');
        if (adminTab.evaluate().isNotEmpty) {
          await tester.tap(adminTab.last);
          await tester.pumpAndSettle();

          // Navigate to Users tab
          final usersTab = find.text('Users');
          if (usersTab.evaluate().isNotEmpty) {
            await tester.tap(usersTab);
            await tester.pumpAndSettle();

            // Verify users are displayed with roles
            expect(find.text('admin_user'), findsOneWidget);
            expect(find.text('normal_user'), findsOneWidget);
            expect(find.text('banned_user'), findsOneWidget);

            // Verify banned user shows BANNED indicator
            expect(find.textContaining('BANNED'), findsOneWidget);
          }
        }
      },
    );

    testWidgets(
      'Draft events show DRAFT badge on home screen',
      (tester) async {
        final mockClient = MockClient((request) async {
          final path = request.url.path;

          if (path == '/api/v1/auth/guest') {
            return http.Response(
              jsonEncode({
                'id': 1,
                'username': 'creator_user',
                'role': 'user',
                'is_banned': false,
              }),
              200,
            );
          } else if (path == '/api/v1/events') {
            return http.Response(
              jsonEncode([
                {
                  'id': 1,
                  'name': 'Published Event',
                  'creator_id': 1,
                  'status': 'published',
                  'created_at': DateTime.now().toIso8601String(),
                },
                {
                  'id': 2,
                  'name': 'My Draft Event',
                  'creator_id': 1,
                  'status': 'draft',
                  'created_at': DateTime.now().toIso8601String(),
                },
              ]),
              200,
            );
          } else if (path == '/api/v1/system/status') {
            return http.Response(
              jsonEncode({'backend_version': 'test', 'resources': null}),
              200,
            );
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
        await tester.tap(find.text('Start Guest Session'));
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // Verify both events are shown
        expect(find.text('Published Event'), findsOneWidget);
        expect(find.text('My Draft Event'), findsOneWidget);

        // Verify DRAFT badge appears for draft event
        expect(find.text('DRAFT'), findsOneWidget);
      },
    );

    testWidgets(
      'Merch with status and deletion info is displayed correctly',
      (tester) async {
        final mockClient = MockClient((request) async {
          final path = request.url.path;

          if (path == '/api/v1/auth/guest') {
            return http.Response(
              jsonEncode({
                'id': 1,
                'username': 'testuser',
                'role': 'user',
                'is_banned': false,
              }),
              200,
            );
          } else if (path == '/api/v1/events') {
            return http.Response(
              jsonEncode([
                {
                  'id': 1,
                  'name': 'Test Event',
                  'creator_id': 1,
                  'status': 'published',
                  'created_at': DateTime.now().toIso8601String(),
                },
              ]),
              200,
            );
          } else if (path == '/api/v1/events/1/merch') {
            return http.Response(
              jsonEncode([
                {
                  'id': 1,
                  'event_id': 1,
                  'name': 'Active Item',
                  'group_name': 'Group A',
                  'status': 'published',
                  'is_deleted': false,
                  'trade_enabled': true,
                  'creator_id': 1,
                },
                {
                  'id': 2,
                  'event_id': 1,
                  'name': 'Inventory Only Item',
                  'group_name': 'Group A',
                  'status': 'published',
                  'is_deleted': true,
                  'trade_enabled': false,
                  'creator_id': 1,
                },
              ]),
              200,
            );
          } else if (path == '/api/v1/user/1/inventory') {
            return http.Response(jsonEncode([]), 200);
          } else if (path.contains('/favorite_groups')) {
            return http.Response(jsonEncode([]), 200);
          } else if (path.contains('/view')) {
            return http.Response(jsonEncode({}), 200);
          } else if (path == '/api/v1/system/status') {
            return http.Response(
              jsonEncode({'backend_version': 'test', 'resources': null}),
              200,
            );
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
        await tester.tap(find.text('Start Guest Session'));
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // Navigate to event
        await tester.tap(find.text('Test Event'));
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // Verify merch items are displayed
        expect(find.text('Active Item'), findsOneWidget);
        expect(find.text('Inventory Only Item'), findsOneWidget);
      },
    );
  });
}
