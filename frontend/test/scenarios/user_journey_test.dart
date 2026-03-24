import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:frontend/main.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockImagePickerPlatform extends ImagePickerPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions? options,
  }) async {
    // Minimal 1x1 transparent PNG
    final bytes = Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]);
    return XFile.fromData(bytes, mimeType: 'image/png', name: 'test_image.png');
  }

  @override
  Future<XFile?> getImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
  }) async {
    return getImageFromSource(source: source);
  }
}

void main() {
  setUp(() async {
    // Clear preferences to ensure we start unauthenticated
    SharedPreferences.setMockInitialValues({});
  });

  group('User Journey Scenarios', () {
    testWidgets(
      'Scenario 1: Guest Login -> Create Event -> Add Merch -> Inventory Management',
      (tester) async {
        int eventCounter = 1;
        int merchCounter = 1;

        // We need a stateful mock backend to handle the sequence
        final mockBackendState = {'events': [], 'merch': [], 'inventory': []};

        final mockClient = MockClient((request) async {
          final path = request.url.path;
          final method = request.method;

          if (path == '/api/v1/auth/guest') {
            return http.Response(
              jsonEncode({
                'id': 1,
                'username': 'guest_test',
                'device_token': 'mock-token',
                'created_at': DateTime.now().toIso8601String(),
                'role': 'user',
                'is_banned': false,
              }),
              200,
            );
          }

          if (path == '/api/v1/users') {
            return http.Response(
              jsonEncode([
                {
                  'id': 1,
                  'username': 'guest_test',
                  'role': 'user',
                  'is_banned': false,
                  'created_at': DateTime.now().toIso8601String(),
                },
              ]),
              200,
            );
          }

          if (path == '/api/v1/system/status') {
            return http.Response(
              jsonEncode({'backend_version': 'test', 'resources': {}}),
              200,
            );
          }

          if (path == '/api/v1/events') {
            if (method == 'GET') {
              return http.Response(jsonEncode(mockBackendState['events']), 200);
            } else if (method == 'POST') {
              final body = jsonDecode(request.body);
              final newEvent = {
                'id': eventCounter++,
                'name': body['name'],
                'creator_id': body['creator_id'],
                'created_at': DateTime.now().toIso8601String(),
                'status': 'published',
              };
              mockBackendState['events']!.add(newEvent);
              return http.Response(jsonEncode(newEvent), 200);
            }
          }

          if (path.startsWith('/api/v1/events/') && path.endsWith('/merch')) {
            if (method == 'GET') {
              return http.Response(jsonEncode(mockBackendState['merch']), 200);
            } else if (method == 'POST') {
              final body = jsonDecode(request.body);
              final newMerch = {
                'id': merchCounter++,
                'event_id': body['event_id'],
                'name': body['name'],
                'group_name': body['group_name'] ?? '',
                'photo_url': body['photo_url'] ?? '',
                'status': 'published',
                'is_deleted': false,
                'trade_enabled': true,
              };
              mockBackendState['merch']!.add(newMerch);
              return http.Response(jsonEncode(newMerch), 200);
            }
          }

          if (path.startsWith('/api/v1/user/1/inventory')) {
            return http.Response(
              jsonEncode(mockBackendState['inventory']),
              200,
            );
          }

          if (path == '/api/v1/user/inventory' && method == 'POST') {
            final body = jsonDecode(request.body);

            // Update or add inventory
            mockBackendState['inventory']!.removeWhere(
              (i) =>
                  i['merch_id'] == body['merch_id'] &&
                  i['status'] == body['status'],
            );
            if (body['quantity'] > 0) {
              mockBackendState['inventory']!.add({
                'id': 99,
                'user_id': body['user_id'],
                'merch_id': body['merch_id'],
                'status': body['status'],
                'quantity': body['quantity'],
                'merch_name': 'mocked',
              });
            }
            return http.Response(
              jsonEncode(mockBackendState['inventory']!.last),
              200,
            );
          }

          return http.Response('Not Found: $path', 404);
        });

        // 1. Boot up the app
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

        // 2. Guest Login
        expect(find.text('Start as New User'), findsOneWidget);
        await tester.tap(find.text('Start as New User'));
        await tester.pumpAndSettle();

        // 3. We are on the Home Screen. Create an Event.
        expect(find.text('New Event'), findsOneWidget);
        await tester.tap(find.text('New Event'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, 'Comic Market 105');
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();

        // Ensure dialog closed
        expect(find.byType(AlertDialog), findsNothing);

        // Ensure it appeared
        expect(find.text('Comic Market 105'), findsOneWidget);

        // 4. Navigate into Event Details
        await tester.tap(find.text('Comic Market 105'));
        await tester.pumpAndSettle();

        expect(find.text('No merchandise yet'), findsWidgets);

        // 5. Add Merch to the Event
        await tester.tap(find.text('Add Merch'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('New Group'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'Stands');
        await tester.tap(find.text('Set'));
        await tester.pumpAndSettle();

        // Verify Image Picking
        ImagePickerPlatform.instance = MockImagePickerPlatform();
        await tester.tap(find.byIcon(Icons.add_a_photo));
        await tester.pumpAndSettle();

        final photoUrlField = find.widgetWithText(
          TextField,
          'Photo URL (Optional)',
        );
        expect(
          tester.widget<TextField>(photoUrlField).controller?.text,
          contains('data:image/png;base64,'),
        );

        await tester.enterText(
          find.widgetWithText(TextField, 'Item Name').first,
          'Acrylic Stand A',
        );
        await tester.tap(find.text('Add Item'));
        await tester.pumpAndSettle();

        // Verify it was saved to backend with the image
        final lastMerch = mockBackendState['merch']!.last;
        expect(lastMerch['name'], 'Acrylic Stand A');
        expect(lastMerch['photo_url'], contains('data:image/png;base64,'));

        // 6. Navigate back from Add Merch sheet
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        // Item should now exist on screen under the "Stands" tab
        expect(find.text('Stands'), findsWidgets);
        await tester.tap(find.text('Stands'));
        await tester.pumpAndSettle();

        expect(find.text('Acrylic Stand A'), findsOneWidget);

        // 7. Inventory Management: Increment HAVE
        final haveIncreaseBtn = find.widgetWithIcon(InkWell, Icons.add).first;
        await tester.tap(haveIncreaseBtn);
        await tester.pumpAndSettle();

        // 8. Increment TRADE
        final tradeIncreaseBtn = find.widgetWithIcon(InkWell, Icons.add).last;
        await tester.tap(tradeIncreaseBtn);
        await tester.pumpAndSettle();

        // Verify state was sent to mock backend
        expect(
          mockBackendState['inventory']!.length,
          2,
        ); // 1 for HAVE, 1 for TRADE
      },
    );

    testWidgets('Scenario 2: Matching Lifecycle -> Accept -> Chat', (
      tester,
    ) async {
      int matchCounter = 1;
      int msgCounter = 1;

      final mockBackendState = {
        'matches': [
          {
            'id': matchCounter++,
            'user1_id': 1,
            'user2_id': 2,
            'status': 'PENDING',
            'created_at': DateTime.now().toIso8601String(),
            'other_user': {
              'id': 2,
              'username': 'trader_bob',
              'role': 'user',
              'is_banned': false,
            },
            'user_haves': [
              {'id': 1, 'merch_name': 'Acrylic Stand A', 'quantity': 1},
            ],
            'user_wants': [
              {'id': 2, 'merch_name': 'Badge B', 'quantity': 1},
            ],
          },
        ],
        'messages': <Map<String, dynamic>>[],
      };

      final mockClient = MockClient((request) async {
        final path = request.url.path;
        final method = request.method;

        if (path == '/api/v1/auth/guest') {
          return http.Response(
            jsonEncode({
              'id': 1,
              'username': 'guest_test',
              'device_token': 'mock-token',
              'created_at': DateTime.now().toIso8601String(),
              'role': 'user',
              'is_banned': false,
            }),
            200,
          );
        }

        if (path.startsWith('/api/v1/matches/user/1')) {
          return http.Response(jsonEncode(mockBackendState['matches']), 200);
        }

        if (path == '/api/v1/matches/trigger') {
          return http.Response(jsonEncode({'matches_created': 0}), 200);
        }

        if (path == '/api/v1/matches/1/status' && method == 'POST') {
          final body = jsonDecode(request.body);
          if (body['status'] == 'ACCEPTED') {
            mockBackendState['matches']![0]['status'] = 'ACCEPTED';
          }
          return http.Response('', 200); // Empty response for 200 OK
        }

        if (path == '/api/v1/matches/1/messages') {
          if (method == 'GET') {
            return http.Response(jsonEncode(mockBackendState['messages']), 200);
          } else if (method == 'POST') {
            final body = jsonDecode(request.body);
            final newMsg = {
              'id': msgCounter++,
              'match_id': 1,
              'sender_id': 1,
              'content': body['content'],
              'created_at': DateTime.now().toIso8601String(),
            };
            mockBackendState['messages']!.add(newMsg);
            return http.Response(jsonEncode(newMsg), 200);
          }
        }

        return http.Response('Not Found: $path', 404);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith((ref) {
              return ApiClient(
                ref.watch(configServiceProvider),
                client: mockClient,
              );
            }),
          ],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Login
      await tester.tap(find.text('Start as New User'));
      await tester.pumpAndSettle();

      // Go to Matches Tab
      await tester.tap(find.text('Matches').last);
      await tester.pumpAndSettle();

      // Ensure PENDING match is visible
      expect(find.text('Trade Match #1'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);

      // Trigger Algorithm (removed since button was moved)

      // Accept Match
      await tester.tap(find.text('Accept Match'));
      await tester.pumpAndSettle();

      // Confirm Dialog
      expect(find.text('Confirm Trade Offer'), findsOneWidget);
      expect(find.text('• Acrylic Stand A'), findsOneWidget);
      expect(find.text('• Badge B'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      // Status should change (though our mock state updated, riverpod invalidates and fetches again)
      // Since it's ACCEPTED now, we should see 'Cancel Trade' instead of 'Reject'
      expect(find.text('Cancel Trade'), findsOneWidget);
      expect(find.text('Mark as Completed'), findsOneWidget);

      // Open Chat
      await tester.tap(find.text('Trade Match #1'));
      await tester.pumpAndSettle();

      expect(find.text('Type a message...'), findsOneWidget);

      // Send a message
      await tester.enterText(
        find.byType(TextField),
        'Hello! Where should we meet?',
      );
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Verify message appears
      expect(find.text('Hello! Where should we meet?'), findsOneWidget);
    });
  });
}
