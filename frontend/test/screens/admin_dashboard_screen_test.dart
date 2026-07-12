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
          eventName: 'Test Event',
          groupName: 'test-group',
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

      expect(find.text('test-group'), findsOneWidget);
      expect(
        find.text('Test Event (Event ID: 42) | 3 live items'),
        findsOneWidget,
      );

      // Cancel leaves data and does not call DELETE.
      await tester.tap(find.byTooltip('Remove group'));
      await tester.pumpAndSettle();
      expect(find.text('Remove item group?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deletedPaths, isEmpty);
      expect(find.text('test-group'), findsOneWidget);

      // Confirm removal issues the URL-encoded DELETE and shows success.
      await tester.tap(find.byTooltip('Remove group'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Remove'));
      await tester.pumpAndSettle();

      final encoded = Uri.encodeComponent('test-group');
      expect(deletedPaths, [
        '/api/v1/admin/events/42/groups/$encoded?user_id=7',
      ]);
      expect(find.text('Item group removed'), findsOneWidget);
    },
  );

  testWidgets(
    'Items tab resolves relative photoUrl via buildImage (#331)',
    (WidgetTester tester) async {
      final merch = Merchandise()
        ..id = 10
        ..eventId = 5
        ..name = 'RelativePhotoMerch'
        ..groupName = 'Pins'
        ..photoUrl = 'uploads/abc.png';

      final mockClient = MockClient(
        (request) async => http.Response('[]', 200),
      );
      final api = ApiClient(
        ConfigService()..setBaseUrlForTest('http://localhost:3000'),
        client: mockClient,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(_adminUser())),
            apiClientProvider.overrideWith((ref) => api),
            adminGroupsProvider.overrideWith((ref) async => <AdminGroup>[]),
            adminMerchProvider.overrideWith((ref) async => [merch]),
            adminMatchesProvider.overrideWith((ref) async => <TradeMatch>[]),
            adminUsersProvider.overrideWith((ref) async => <User>[]),
            eventsProvider.overrideWith((ref) async => <Event>[]),
            backendSystemStatusProvider.overrideWith(
              (ref) async => <String, dynamic>{},
            ),
          ],
          child: const MaterialApp(home: AdminDashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Items'));
      await tester.pumpAndSettle();

      expect(find.text('RelativePhotoMerch'), findsOneWidget);

      // buildImage → resolveImageUrl turns relative paths into absolute
      // backend URLs (non-web tests resolve to http://localhost:3000/...).
      // Direct Image.network(item.photoUrl) would leave "uploads/abc.png"
      // unresolved and fail to load.
      final Image image = tester.widget(find.byType(Image));
      expect(image.image, isA<NetworkImage>());
      expect(
        (image.image as NetworkImage).url,
        'http://localhost:3000/uploads/abc.png',
      );
      expect(image.fit, BoxFit.contain);
      expect(image.width, 50);
      expect(image.height, 50);
    },
  );

  testWidgets(
    'Items tab shows placeholder when photoUrl is empty (#331)',
    (WidgetTester tester) async {
      final merch = Merchandise()
        ..id = 11
        ..eventId = 5
        ..name = 'NoPhotoMerch'
        ..groupName = 'Pins';

      final mockClient = MockClient(
        (request) async => http.Response('[]', 200),
      );
      final api = ApiClient(
        ConfigService()..setBaseUrlForTest('http://localhost:3000'),
        client: mockClient,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(_adminUser())),
            apiClientProvider.overrideWith((ref) => api),
            adminGroupsProvider.overrideWith((ref) async => <AdminGroup>[]),
            adminMerchProvider.overrideWith((ref) async => [merch]),
            adminMatchesProvider.overrideWith((ref) async => <TradeMatch>[]),
            adminUsersProvider.overrideWith((ref) async => <User>[]),
            eventsProvider.overrideWith((ref) async => <Event>[]),
            backendSystemStatusProvider.overrideWith(
              (ref) async => <String, dynamic>{},
            ),
          ],
          child: const MaterialApp(home: AdminDashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Items'));
      await tester.pumpAndSettle();

      expect(find.text('NoPhotoMerch'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      // buildImage default placeholder uses image_outlined, not Icons.image.
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    },
  );
}
