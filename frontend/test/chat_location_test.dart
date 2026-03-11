import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:frontend/main.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Chat Location Sharing Test', () {
    testWidgets('Share location in chat and verify it appears', (tester) async {
      bool messageSent = false;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/guest') {
          return http.Response(jsonEncode({
            'id': 1,
            'username': 'guest123',
            'device_token': 'mock-token',
            'created_at': DateTime.now().toIso8601String(),
          }), 200);
        } else if (request.url.path == '/api/v1/events') {
          return http.Response(jsonEncode([]), 200);
        } else if (request.url.path == '/api/v1/system/status') {
          return http.Response(jsonEncode({'backend_version': '1.0.0'}), 200);
        } else if (request.url.path == '/api/v1/matches/user/1') {
          return http.Response(jsonEncode([{
            'id': 100,
            'user1_id': 1,
            'user2_id': 2,
            'status': 'ACCEPTED',
            'other_user': {'id': 2, 'username': 'other_user'},
            'user_haves': [],
            'user_wants': [],
          }]), 200);
        } else if (request.url.path == '/api/v1/matches/100/messages') {
          if (request.method == 'GET') {
            if (messageSent) {
              return http.Response(jsonEncode([{
                'id': 1001,
                'match_id': 100,
                'sender_id': 1,
                'content': 'https://www.google.com/maps/search/?api=1&query=35.6895,139.6917',
                'created_at': '2023-01-01T00:00:00Z',
              }]), 200);
            }
            return http.Response(jsonEncode([]), 200);
          } else if (request.method == 'POST') {
            messageSent = true;
            return http.Response(jsonEncode({}), 200);
          }
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

      // 1. Login
      await tester.tap(find.text('Start Guest Session'));
      await tester.pumpAndSettle();

      // 2. Navigate to Matches
      await tester.tap(find.text('Matches').last);
      await tester.pumpAndSettle();

      // 3. Enter Chat
      await tester.tap(find.text('Trade Match #100'));
      await tester.pumpAndSettle();

      // 4. Open Map Picker
      await tester.tap(find.byIcon(Icons.add_location_alt_outlined));
      await tester.pumpAndSettle();

      // 5. Confirm Location
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      // 6. Verify message sent and displayed
      expect(messageSent, isTrue);

      // Wait for polling to fetch the new message (polling is every 3 seconds)
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text('Open in Maps'), findsOneWidget);
    });
  });
}
