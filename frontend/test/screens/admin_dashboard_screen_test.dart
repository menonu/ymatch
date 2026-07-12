// Widget tests for the admin Groups tab (#380).
//
// Covers listing groups with event context and the destructive confirmation
// flow that issues a URL-encoded DELETE for group removal.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/screens/admin_dashboard_screen.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

User _adminUser() => User()
  ..id = 7
  ..username = 'admin_user'
  ..role = 'admin';

class _MockAuthController extends StateNotifier<AsyncValue<User?>>
    implements AuthController {
  _MockAuthController(User user) : super(AsyncValue.data(user));

  @override
  Future<void> checkLogin() async {}

  @override
  Future<void> startGuestSession() async {}

  @override
  Future<void> guestLogin(String uuid) async {}

  @override
  Future<void> restoreAccount(String uuid) async {}

  @override
  Future<void> login(String username, String password) async {}

  @override
  Future<void> signup(String username, String password) async {}

  @override
  void logout() {}

  @override
  Future<void> updateUsername(int userId, String newUsername) async {}

  @override
  get client => throw UnimplementedError();
}

void main() {
  testWidgets(
    'Groups tab lists groups and confirmed remove issues encoded DELETE (#380)',
    (WidgetTester tester) async {
      final deletedPaths = <String>[];
      var groups = <AdminGroup>[
        const AdminGroup(
          eventId: 42,
          eventName: '2026 *Tibbar tibbar!*',
          groupName: 'アクスタ',
          itemCount: 3,
        ),
      ];

      final mockClient = MockClient((request) async {
        if (request.method == 'DELETE' &&
            request.url.path.startsWith('/api/v1/admin/events/')) {
          deletedPaths.add(
            '${request.url.path}?${request.url.query}',
          );
          return http.Response('', 200);
        }
        return http.Response('[]', 200);
      });
      final api = ApiClient(
        ConfigService()..setBaseUrlForTest('http://localhost:3000'),
        client: mockClient,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(_adminUser())),
            apiClientProvider.overrideWith((ref) => api),
            adminGroupsProvider.overrideWith((ref) async => groups),
            adminMerchProvider.overrideWith((ref) async => <Merchandise>[]),
            adminMatchesProvider.overrideWith((ref) async => <TradeMatch>[]),
            adminUsersProvider.overrideWith((ref) async => <User>[]),
            eventsProvider.overrideWith((ref) async => <Event>[]),
            backendSystemStatusProvider.overrideWith((ref) async => <String, dynamic>{}),
          ],
          child: const MaterialApp(home: AdminDashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Open the Groups tab.
      await tester.tap(find.text('Groups'));
      await tester.pumpAndSettle();

      expect(find.text('アクスタ'), findsOneWidget);
      expect(
        find.text('2026 *Tibbar tibbar!* (Event ID: 42) | 3 live items'),
        findsOneWidget,
      );

      // Cancel leaves data and does not call DELETE.
      await tester.tap(find.byTooltip('Remove group'));
      await tester.pumpAndSettle();
      expect(find.text('Remove item group?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deletedPaths, isEmpty);
      expect(find.text('アクスタ'), findsOneWidget);

      // Confirm removal issues the URL-encoded DELETE and shows success.
      await tester.tap(find.byTooltip('Remove group'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Remove'));
      await tester.pumpAndSettle();

      final encoded = Uri.encodeComponent('アクスタ');
      expect(deletedPaths, [
        '/api/v1/admin/events/42/groups/$encoded?user_id=7',
      ]);
      expect(find.text('Item group removed'), findsOneWidget);
    },
  );
}
