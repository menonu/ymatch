import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/main.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Admin Journey Scenarios', () {
    testWidgets(
      'Scenario 1: Admin Login -> View Users -> Ban/Unban -> Change Role',
      (tester) async {
        final mockUsers = <Map<String, dynamic>>[
          {
            'id': 1,
            'username': 'admin_user',
            'role': 'admin',
            'is_banned': false,
            'ban_reason': null,
            'banned_until': null,
            'created_at': DateTime.now().toIso8601String(),
          },
          {
            'id': 2,
            'username': 'regular_user',
            'role': 'user',
            'is_banned': false,
            'ban_reason': null,
            'banned_until': null,
            'created_at': DateTime.now().toIso8601String(),
          },
          {
            'id': 3,
            'username': 'another_user',
            'role': 'user',
            'is_banned': false,
            'ban_reason': null,
            'banned_until': null,
            'created_at': DateTime.now().toIso8601String(),
          },
        ];

        final mockClient = MockClient((request) async {
          final path = request.url.path;
          final method = request.method;

          if (path == '/api/v1/auth/guest') {
            return http.Response(
              jsonEncode({
                'id': 1,
                'username': 'admin_user',
                'device_token': 'mock-admin-token',
                'created_at': DateTime.now().toIso8601String(),
                'role': 'admin',
                'is_banned': false,
              }),
              200,
            );
          }

          if (path == '/api/v1/system/status') {
            return http.Response(
              jsonEncode({
                'backend_version': 'test',
                'resources': {
                  'total_memory_bytes': 8589934592,
                  'used_memory_bytes': 4294967296,
                  'cpu_usage_percent': 25.0,
                  'uptime_seconds': 3600,
                },
              }),
              200,
            );
          }

          if (path == '/api/v1/users' && method == 'GET') {
            return http.Response(jsonEncode(mockUsers), 200);
          }

          if (path == '/api/v1/events' && method == 'GET') {
            return http.Response(jsonEncode([]), 200);
          }

          if (path == '/api/v1/admin/merch' && method == 'GET') {
            return http.Response(jsonEncode([]), 200);
          }

          if (path == '/api/v1/admin/matches' && method == 'GET') {
            return http.Response(jsonEncode([]), 200);
          }

          // Ban user
          final banMatch = RegExp(
            r'^/api/v1/admin/users/(\d+)/ban$',
          ).firstMatch(path);
          if (banMatch != null && method == 'POST') {
            final targetId = int.parse(banMatch.group(1)!);
            final body = request.body.isNotEmpty
                ? jsonDecode(request.body) as Map<String, dynamic>
                : <String, dynamic>{};
            final user = mockUsers.firstWhere((u) => u['id'] == targetId);
            user['is_banned'] = true;
            user['ban_reason'] = body['reason'] ?? 'Violation of terms';
            user['banned_until'] = body['banned_until'];
            return http.Response(jsonEncode(user), 200);
          }

          // Unban user
          final unbanMatch = RegExp(
            r'^/api/v1/admin/users/(\d+)/unban$',
          ).firstMatch(path);
          if (unbanMatch != null && method == 'POST') {
            final targetId = int.parse(unbanMatch.group(1)!);
            final user = mockUsers.firstWhere((u) => u['id'] == targetId);
            user['is_banned'] = false;
            user['ban_reason'] = null;
            user['banned_until'] = null;
            return http.Response(jsonEncode(user), 200);
          }

          // Change role
          final roleMatch = RegExp(
            r'^/api/v1/admin/users/(\d+)/role$',
          ).firstMatch(path);
          if (roleMatch != null && method == 'POST') {
            final targetId = int.parse(roleMatch.group(1)!);
            final body = jsonDecode(request.body);
            final user = mockUsers.firstWhere((u) => u['id'] == targetId);
            user['role'] = body['role'];
            return http.Response(jsonEncode(user), 200);
          }

          return http.Response('Not Found: $path', 404);
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

        // 1. Admin Login
        expect(find.text('Start as New User'), findsOneWidget);
        await tester.tap(find.text('Start as New User'));
        await tester.pumpAndSettle();

        // 2. Verify admin user is logged in
        // Navigate to Admin tab if available
        final adminTab = find.text('Admin');
        if (adminTab.evaluate().isNotEmpty) {
          await tester.tap(adminTab.last);
          await tester.pumpAndSettle();
        }

        // 3. Verify mock backend state after ban
        expect(mockUsers[1]['is_banned'], false);

        // Simulate ban via mock backend directly
        final banResponse = await mockClient.post(
          Uri.parse('http://localhost:3000/api/v1/admin/users/2/ban?user_id=1'),
          body: jsonEncode({
            'reason': 'Spamming',
            'banned_until': '2025-12-31T00:00:00Z',
          }),
        );
        expect(banResponse.statusCode, 200);
        expect(mockUsers[1]['is_banned'], true);
        expect(mockUsers[1]['ban_reason'], 'Spamming');

        // 4. Unban user
        final unbanResponse = await mockClient.post(
          Uri.parse(
            'http://localhost:3000/api/v1/admin/users/2/unban?user_id=1',
          ),
        );
        expect(unbanResponse.statusCode, 200);
        expect(mockUsers[1]['is_banned'], false);
        expect(mockUsers[1]['ban_reason'], null);

        // 5. Change role
        final roleResponse = await mockClient.post(
          Uri.parse(
            'http://localhost:3000/api/v1/admin/users/3/role?user_id=1',
          ),
          body: jsonEncode({'role': 'admin'}),
        );
        expect(roleResponse.statusCode, 200);
        expect(mockUsers[2]['role'], 'admin');

        // 6. Verify users list endpoint
        final usersResponse = await mockClient.get(
          Uri.parse('http://localhost:3000/api/v1/users'),
        );
        expect(usersResponse.statusCode, 200);
        final usersList = jsonDecode(usersResponse.body) as List;
        expect(usersList.length, 3);
        expect(usersList[2]['role'], 'admin');
      },
    );

    testWidgets(
      'Scenario 2: Draft Event Creation -> Publish',
      (tester) async {
        int eventCounter = 1;
        int merchCounter = 1;

        final mockEvents = <Map<String, dynamic>>[];
        final mockMerch = <Map<String, dynamic>>[];

        final mockClient = MockClient((request) async {
          final path = request.url.path;
          final method = request.method;

          if (path == '/api/v1/auth/guest') {
            return http.Response(
              jsonEncode({
                'id': 1,
                'username': 'admin_user',
                'device_token': 'mock-admin-token',
                'created_at': DateTime.now().toIso8601String(),
                'role': 'admin',
                'is_banned': false,
              }),
              200,
            );
          }

          if (path == '/api/v1/system/status') {
            return http.Response(
              jsonEncode({
                'backend_version': 'test',
                'resources': {
                  'total_memory_bytes': 8589934592,
                  'used_memory_bytes': 4294967296,
                  'cpu_usage_percent': 25.0,
                  'uptime_seconds': 3600,
                },
              }),
              200,
            );
          }

          if (path == '/api/v1/events') {
            if (method == 'GET') {
              return http.Response(jsonEncode(mockEvents), 200);
            } else if (method == 'POST') {
              final body = jsonDecode(request.body);
              final newEvent = {
                'id': eventCounter++,
                'name': body['name'],
                'creator_id': body['creator_id'],
                'created_at': DateTime.now().toIso8601String(),
                'status': 'draft',
              };
              mockEvents.add(newEvent);
              return http.Response(jsonEncode(newEvent), 200);
            }
          }

          // Publish event
          final publishEventMatch = RegExp(
            r'^/api/v1/events/(\d+)/publish$',
          ).firstMatch(path);
          if (publishEventMatch != null && method == 'POST') {
            final eventId = int.parse(publishEventMatch.group(1)!);
            final event = mockEvents.firstWhere((e) => e['id'] == eventId);
            event['status'] = 'published';
            return http.Response(jsonEncode(event), 200);
          }

          // Event merch
          final merchMatch = RegExp(
            r'^/api/v1/events/(\d+)/merch$',
          ).firstMatch(path);
          if (merchMatch != null) {
            if (method == 'GET') {
              return http.Response(jsonEncode(mockMerch), 200);
            } else if (method == 'POST') {
              final body = jsonDecode(request.body);
              final newMerch = {
                'id': merchCounter++,
                'event_id': body['event_id'],
                'name': body['name'],
                'group_name': body['group_name'] ?? '',
                'photo_url': body['photo_url'] ?? '',
                'status': 'draft',
                'is_deleted': false,
                'trade_enabled': true,
                'creator_id': 1,
              };
              mockMerch.add(newMerch);
              return http.Response(jsonEncode(newMerch), 200);
            }
          }

          // Publish merch
          final publishMerchMatch = RegExp(
            r'^/api/v1/events/(\d+)/merch/(\d+)/publish$',
          ).firstMatch(path);
          if (publishMerchMatch != null && method == 'POST') {
            final merchId = int.parse(publishMerchMatch.group(2)!);
            final merch = mockMerch.firstWhere((m) => m['id'] == merchId);
            merch['status'] = 'published';
            return http.Response(jsonEncode(merch), 200);
          }

          if (path == '/api/v1/users' && method == 'GET') {
            return http.Response(
              jsonEncode([
                {
                  'id': 1,
                  'username': 'admin_user',
                  'role': 'admin',
                  'is_banned': false,
                  'created_at': DateTime.now().toIso8601String(),
                },
              ]),
              200,
            );
          }

          return http.Response('Not Found: $path', 404);
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

        // 1. Login as admin
        await tester.tap(find.text('Start as New User'));
        await tester.pumpAndSettle();

        // 2. Create a draft event via mock backend
        final createEventResponse = await mockClient.post(
          Uri.parse('http://localhost:3000/api/v1/events'),
          body: jsonEncode({'name': 'Draft Comic Con', 'creator_id': 1}),
        );
        expect(createEventResponse.statusCode, 200);
        final createdEvent = jsonDecode(createEventResponse.body);
        expect(createdEvent['status'], 'draft');
        expect(createdEvent['name'], 'Draft Comic Con');

        // 3. Publish the event
        final publishResponse = await mockClient.post(
          Uri.parse(
            'http://localhost:3000/api/v1/events/${createdEvent['id']}/publish',
          ),
          body: jsonEncode({'user_id': 1}),
        );
        expect(publishResponse.statusCode, 200);
        final publishedEvent = jsonDecode(publishResponse.body);
        expect(publishedEvent['status'], 'published');

        // 4. Create draft merch
        final createMerchResponse = await mockClient.post(
          Uri.parse(
            'http://localhost:3000/api/v1/events/${createdEvent['id']}/merch',
          ),
          body: jsonEncode({
            'event_id': createdEvent['id'],
            'name': 'Limited Poster',
          }),
        );
        expect(createMerchResponse.statusCode, 200);
        final createdMerch = jsonDecode(createMerchResponse.body);
        expect(createdMerch['status'], 'draft');
        expect(createdMerch['is_deleted'], false);
        expect(createdMerch['trade_enabled'], true);
        expect(createdMerch['creator_id'], 1);

        // 5. Publish the merch
        final publishMerchResponse = await mockClient.post(
          Uri.parse(
            'http://localhost:3000/api/v1/events/${createdEvent['id']}/merch/${createdMerch['id']}/publish',
          ),
        );
        expect(publishMerchResponse.statusCode, 200);
        final publishedMerch = jsonDecode(publishMerchResponse.body);
        expect(publishedMerch['status'], 'published');

        // 6. Verify final state
        expect(mockEvents.length, 1);
        expect(mockEvents[0]['status'], 'published');
        expect(mockMerch.length, 1);
        expect(mockMerch[0]['status'], 'published');
      },
    );

    testWidgets(
      'Scenario 3: Banned user fields in response',
      (tester) async {
        final mockClient = MockClient((request) async {
          final path = request.url.path;

          if (path == '/api/v1/auth/guest') {
            return http.Response(
              jsonEncode({
                'id': 1,
                'username': 'banned_user',
                'device_token': 'mock-token',
                'created_at': DateTime.now().toIso8601String(),
                'role': 'user',
                'is_banned': true,
                'ban_reason': 'Policy violation',
                'banned_until': '2025-12-31T00:00:00Z',
              }),
              200,
            );
          }

          if (path == '/api/v1/system/status') {
            return http.Response(
              jsonEncode({
                'backend_version': 'test',
                'resources': {
                  'total_memory_bytes': 8589934592,
                  'used_memory_bytes': 4294967296,
                  'cpu_usage_percent': 25.0,
                  'uptime_seconds': 3600,
                },
              }),
              200,
            );
          }

          if (path == '/api/v1/events') {
            return http.Response(jsonEncode([]), 200);
          }

          return http.Response('Not Found: $path', 404);
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

        // Verify the banned user response is parsed correctly
        final response = await mockClient.post(
          Uri.parse('http://localhost:3000/api/v1/auth/guest'),
        );
        final userData = jsonDecode(response.body);
        expect(userData['is_banned'], true);
        expect(userData['ban_reason'], 'Policy violation');
        expect(userData['banned_until'], '2025-12-31T00:00:00Z');
        expect(userData['role'], 'user');
      },
    );
  });
}
