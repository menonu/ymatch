// Widget tests for the admin Groups tab (#380).
//
// Covers listing groups with event context and the destructive confirmation
// flow that issues a URL-encoded DELETE for group removal.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/screens/admin_dashboard_screen.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Admin dashboard under a localized [MaterialApp] so shared member dialogs
/// (#446) resolve [AppLocalizations] the same way production does.
Widget _adminApp(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

User _adminUser() => User()
  ..id = 7
  ..username = 'admin_user'
  ..role = 'admin';

class _MockAuthController extends StateNotifier<AsyncValue<User?>>
    implements AuthController {
  _MockAuthController(User? user) : super(AsyncValue.data(user));

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
          deletedPaths.add('${request.url.path}?${request.url.query}');
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
            authProvider.overrideWith(
              (ref) => _MockAuthController(_adminUser()),
            ),
            apiClientProvider.overrideWith((ref) => api),
            adminGroupsProvider.overrideWith((ref) async => groups),
            adminMerchProvider.overrideWith((ref) async => <Merchandise>[]),
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

      // Open the Groups tab.
      await tester.tap(find.text('Groups'));
      await tester.pumpAndSettle();

      expect(find.text('test-group'), findsOneWidget);
      expect(
        find.text(
          'Test Event (Event ID: 42) | Creator: Unowned | 3 live items',
        ),
        findsOneWidget,
      );

      // Cancel leaves data and does not call DELETE.
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove item group?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deletedPaths, isEmpty);
      expect(find.text('test-group'), findsOneWidget);

      // Confirm removal issues the URL-encoded DELETE and shows success.
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
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
    'Groups tab shows displayName and falls back to groupName (#430)',
    (WidgetTester tester) async {
      final deletedPaths = <String>[];
      final groups = <AdminGroup>[
        const AdminGroup(
          eventId: 42,
          eventName: 'Test Event',
          groupName: 'pins-key',
          displayName: 'Enamel Pins!',
          itemCount: 2,
        ),
        const AdminGroup(
          eventId: 42,
          eventName: 'Test Event',
          groupName: 'stickers-key',
          itemCount: 1,
        ),
      ];

      final mockClient = MockClient((request) async {
        if (request.method == 'DELETE' &&
            request.url.path.startsWith('/api/v1/admin/events/')) {
          deletedPaths.add('${request.url.path}?${request.url.query}');
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
            authProvider.overrideWith(
              (ref) => _MockAuthController(_adminUser()),
            ),
            apiClientProvider.overrideWith((ref) => api),
            adminGroupsProvider.overrideWith((ref) async => groups),
            adminMerchProvider.overrideWith((ref) async => <Merchandise>[]),
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

      await tester.tap(find.text('Groups'));
      await tester.pumpAndSettle();

      // List title uses displayName when set, otherwise the key.
      expect(find.text('Enamel Pins!'), findsOneWidget);
      expect(find.text('pins-key'), findsNothing);
      expect(find.text('stickers-key'), findsOneWidget);

      // Remove confirmation also shows the friendly label.
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Remove “Enamel Pins!” from “Test Event”?'),
        findsOneWidget,
      );

      // DELETE still targets the immutable group_name key, not the label.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Remove'));
      await tester.pumpAndSettle();
      final encoded = Uri.encodeComponent('pins-key');
      expect(deletedPaths, [
        '/api/v1/admin/events/42/groups/$encoded?user_id=7',
      ]);
    },
  );

  testWidgets('Groups tab change creator issues PUT with newCreatorId (#432)', (
    WidgetTester tester,
  ) async {
    final putPaths = <String>[];
    String? putBody;
    final groups = <AdminGroup>[
      const AdminGroup(
        eventId: 42,
        eventName: 'Test Event',
        groupName: 'pins',
        creatorId: 1,
        creatorUsername: 'alice',
        itemCount: 1,
      ),
    ];
    final users = <User>[
      User()
        ..id = 1
        ..username = 'alice'
        ..role = 'user',
      User()
        ..id = 9
        ..username = 'bob'
        ..role = 'user',
    ];

    final mockClient = MockClient((request) async {
      if (request.method == 'PUT' && request.url.path.contains('/creator')) {
        putPaths.add('${request.url.path}?${request.url.query}');
        putBody = request.body;
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
          adminUsersProvider.overrideWith((ref) async => users),
          eventsProvider.overrideWith((ref) async => <Event>[]),
          backendSystemStatusProvider.overrideWith(
            (ref) async => <String, dynamic>{},
          ),
        ],
        child: const MaterialApp(home: AdminDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Groups'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Test Event (Event ID: 42) | Creator: alice (1) | 1 live items',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change creator'));
    await tester.pumpAndSettle();

    expect(find.text('Change group creator'), findsOneWidget);
    await tester.tap(find.text('bob'));
    await tester.pumpAndSettle();

    expect(putPaths, ['/api/v1/admin/events/42/groups/pins/creator?user_id=7']);
    expect(putBody, contains('newCreatorId'));
    expect(putBody, contains('9'));
    expect(find.text('Group creator updated'), findsOneWidget);
  });

  testWidgets('Events tab change creator and manage editors (#432)', (
    WidgetTester tester,
  ) async {
    final putPaths = <String>[];
    final postPaths = <String>[];
    final event = Event()
      ..id = 11
      ..name = 'Live Event'
      ..creatorId = 1
      ..status = 'published';
    final users = <User>[
      User()
        ..id = 1
        ..username = 'alice'
        ..role = 'user',
      User()
        ..id = 2
        ..username = 'carol'
        ..role = 'user',
    ];

    final mockClient = MockClient((request) async {
      if (request.method == 'PUT' && request.url.path.endsWith('/creator')) {
        putPaths.add('${request.url.path}?${request.url.query}');
        return http.Response('', 200);
      }
      if (request.method == 'GET' && request.url.path.endsWith('/members')) {
        return http.Response(
          '{"members":[{"userId":1,"role":"creator","username":"alice"}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST' && request.url.path.contains('/members/')) {
        postPaths.add('${request.url.path}?${request.url.query}');
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
          adminGroupsProvider.overrideWith((ref) async => <AdminGroup>[]),
          adminMerchProvider.overrideWith((ref) async => <Merchandise>[]),
          adminMatchesProvider.overrideWith((ref) async => <TradeMatch>[]),
          adminUsersProvider.overrideWith((ref) async => users),
          eventsProvider.overrideWith((ref) async => [event]),
          backendSystemStatusProvider.overrideWith(
            (ref) async => <String, dynamic>{},
          ),
        ],
        child: _adminApp(const AdminDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Creator: alice (1)'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change creator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('carol'));
    await tester.pumpAndSettle();

    expect(putPaths, ['/api/v1/admin/events/11/creator?user_id=7']);
    expect(find.text('Event creator updated'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage editors'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Editors — Live Event'), findsOneWidget);
    expect(find.text('alice (1)'), findsOneWidget);
    expect(find.text('creator'), findsOneWidget);

    await tester.tap(find.text('Add editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('carol'));
    await tester.pumpAndSettle();

    expect(postPaths, ['/api/v1/admin/events/11/members/2?user_id=7']);
  });

  test(
    'AdminGroup.label falls back when displayName is null or empty (#430)',
    () {
      expect(
        const AdminGroup(
          eventId: 1,
          eventName: 'E',
          groupName: 'key',
          displayName: 'Nice',
          itemCount: 0,
        ).label,
        'Nice',
      );
      expect(
        const AdminGroup(
          eventId: 1,
          eventName: 'E',
          groupName: 'key',
          itemCount: 0,
        ).label,
        'key',
      );
      expect(
        const AdminGroup(
          eventId: 1,
          eventName: 'E',
          groupName: 'key',
          displayName: '',
          itemCount: 0,
        ).label,
        'key',
      );
    },
  );

  test('AdminGroup.fromJson parses optional displayName (#430)', () {
    final withName = AdminGroup.fromJson({
      'eventId': 1,
      'eventName': 'E',
      'groupName': 'key',
      'displayName': 'Label',
      'itemCount': 2,
    });
    expect(withName.displayName, 'Label');
    expect(withName.label, 'Label');

    final without = AdminGroup.fromJson({
      'eventId': 1,
      'eventName': 'E',
      'groupName': 'key',
      'itemCount': 0,
    });
    expect(without.displayName, isNull);
    expect(without.label, 'key');
  });

  test('AdminGroup.fromJson and creatorLabel (#432)', () {
    final full = AdminGroup.fromJson({
      'eventId': 1,
      'eventName': 'E',
      'groupName': 'key',
      'creatorId': 5,
      'creatorUsername': 'bob',
      'itemCount': 1,
    });
    expect(full.creatorId, 5);
    expect(full.creatorUsername, 'bob');
    expect(full.creatorLabel, 'bob (5)');

    final idOnly = AdminGroup.fromJson({
      'eventId': 1,
      'eventName': 'E',
      'groupName': 'key',
      'creatorId': 5,
      'itemCount': 0,
    });
    expect(idOnly.creatorLabel, 'ID 5');

    final unowned = AdminGroup.fromJson({
      'eventId': 1,
      'eventName': 'E',
      'groupName': 'key',
      'itemCount': 0,
    });
    expect(unowned.creatorLabel, 'Unowned');
  });

  testWidgets('Items tab resolves relative photoUrl via buildImage (#331)', (
    WidgetTester tester,
  ) async {
    final merch = Merchandise()
      ..id = 10
      ..eventId = 5
      ..name = 'RelativePhotoMerch'
      ..groupName = 'Pins'
      ..photoUrl = 'uploads/abc.png';

    final mockClient = MockClient((request) async => http.Response('[]', 200));
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
  });

  testWidgets('Items tab shows placeholder when photoUrl is empty (#331)', (
    WidgetTester tester,
  ) async {
    final merch = Merchandise()
      ..id = 11
      ..eventId = 5
      ..name = 'NoPhotoMerch'
      ..groupName = 'Pins';

    final mockClient = MockClient((request) async => http.Response('[]', 200));
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
  });

  testWidgets(
    'Users tab role-change failure shows error SnackBar (no success) (#395)',
    (WidgetTester tester) async {
      final target = User()
        ..id = 99
        ..username = 'target_user'
        ..role = 'user';

      final mockClient = MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/admin/users/99/role') {
          return http.Response('Forbidden', 403);
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
            authProvider.overrideWith(
              (ref) => _MockAuthController(_adminUser()),
            ),
            apiClientProvider.overrideWith((ref) => api),
            adminGroupsProvider.overrideWith((ref) async => <AdminGroup>[]),
            adminMerchProvider.overrideWith((ref) async => <Merchandise>[]),
            adminMatchesProvider.overrideWith((ref) async => <TradeMatch>[]),
            adminUsersProvider.overrideWith((ref) async => [target]),
            eventsProvider.overrideWith((ref) async => <Event>[]),
            backendSystemStatusProvider.overrideWith(
              (ref) async => <String, dynamic>{},
            ),
          ],
          child: const MaterialApp(home: AdminDashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Users'));
      await tester.pumpAndSettle();
      expect(find.text('target_user'), findsOneWidget);

      // Open the per-user actions menu and pick a role change (no reason dialog).
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🛡️ Set Moderator'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Error:'), findsOneWidget);
      // Must not take the silent invalidate / success-only path.
      expect(find.text('Role updated to moderator'), findsNothing);
    },
  );

  testWidgets(
    'Debug generate failure shows error SnackBar and not success (#395)',
    (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        // generateDebugData starts with POST /api/v1/events.
        if (request.method == 'POST' && request.url.path == '/api/v1/events') {
          return http.Response('Internal Server Error', 500);
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
            authProvider.overrideWith(
              (ref) => _MockAuthController(_adminUser()),
            ),
            apiClientProvider.overrideWith((ref) => api),
            adminGroupsProvider.overrideWith((ref) async => <AdminGroup>[]),
            adminMerchProvider.overrideWith((ref) async => <Merchandise>[]),
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

      await tester.tap(find.text('Debug'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate Test Event (50 items in 5 tabs)'));
      await tester.pumpAndSettle();
      expect(find.text('Generate Data?'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Generate'));
      // The UI first shows "Generating data...", then on failure queues
      // "Failed to generate…". SnackBar transitions need stepped pumps (a single
      // large pump can skip intermediate hide/show frames) (#395).
      await tester.pump(); // close dialog + schedule async work
      await tester.pump(const Duration(milliseconds: 50)); // await mock POST
      expect(find.text('Generating data...'), findsOneWidget);

      // #266/#395: must never claim success, even while the first SnackBar is up.
      expect(find.text('Test data generated successfully!'), findsNothing);

      // Advance in 1s steps until the queued failure SnackBar is visible.
      final failed = find.textContaining('Failed to generate test data:');
      var sawFailure = false;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (failed.evaluate().isNotEmpty) {
          sawFailure = true;
          break;
        }
        // Success must never appear at any intermediate step.
        expect(find.text('Test data generated successfully!'), findsNothing);
      }
      expect(sawFailure, isTrue, reason: 'error SnackBar never became visible');
      expect(failed, findsOneWidget);
      expect(find.text('Test data generated successfully!'), findsNothing);
    },
  );

  // ---- #454: permission / empty / error branches ----

  testWidgets('non-admin user is denied access to the admin dashboard (#454)', (
    WidgetTester tester,
  ) async {
    final regular = User()
      ..id = 3
      ..username = 'regular'
      ..role = 'user';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthController(regular)),
          backendSystemStatusProvider.overrideWith(
            (ref) async => <String, dynamic>{},
          ),
        ],
        child: const MaterialApp(home: AdminDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Access denied. Admin or moderator role required.'),
      findsOneWidget,
    );
    expect(find.text('System'), findsNothing);
    expect(find.text('Users'), findsNothing);
  });

  testWidgets('null user is denied access to the admin dashboard (#454)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthController(null)),
          backendSystemStatusProvider.overrideWith(
            (ref) async => <String, dynamic>{},
          ),
        ],
        child: const MaterialApp(home: AdminDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Access denied. Admin or moderator role required.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'empty tabs and missing system resources show empty-state copy (#454)',
    (WidgetTester tester) async {
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
            authProvider.overrideWith(
              (ref) => _MockAuthController(_adminUser()),
            ),
            apiClientProvider.overrideWith((ref) => api),
            adminGroupsProvider.overrideWith((ref) async => <AdminGroup>[]),
            adminMerchProvider.overrideWith((ref) async => <Merchandise>[]),
            adminMatchesProvider.overrideWith((ref) async => <TradeMatch>[]),
            adminUsersProvider.overrideWith((ref) async => <User>[]),
            eventsProvider.overrideWith((ref) async => <Event>[]),
            backendSystemStatusProvider.overrideWith(
              (ref) async => <String, dynamic>{
                // resources null → System tab empty/error copy.
              },
            ),
          ],
          child: const MaterialApp(home: AdminDashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // System tab (default): missing resources map.
      expect(find.text('Failed to load system resources.'), findsOneWidget);

      await tester.tap(find.text('Users'));
      await tester.pumpAndSettle();
      expect(find.text('No users found.'), findsOneWidget);

      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();
      expect(find.text('No events found.'), findsOneWidget);

      await tester.tap(find.text('Groups'));
      await tester.pumpAndSettle();
      expect(find.text('No groups found.'), findsOneWidget);

      await tester.tap(find.text('Items'));
      await tester.pumpAndSettle();
      expect(find.text('No items found.'), findsOneWidget);

      await tester.tap(find.text('Matches'));
      await tester.pumpAndSettle();
      expect(find.text('No matches found.'), findsOneWidget);
    },
  );

  testWidgets('Users tab provider error surfaces Error: prefix (#454)', (
    WidgetTester tester,
  ) async {
    final mockClient = MockClient((request) async => http.Response('[]', 200));
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
          adminMerchProvider.overrideWith((ref) async => <Merchandise>[]),
          adminMatchesProvider.overrideWith((ref) async => <TradeMatch>[]),
          adminUsersProvider.overrideWith((ref) async {
            throw Exception('users boom');
          }),
          eventsProvider.overrideWith((ref) async => <Event>[]),
          backendSystemStatusProvider.overrideWith(
            (ref) async => <String, dynamic>{},
          ),
        ],
        child: const MaterialApp(home: AdminDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Error:'), findsOneWidget);
    expect(find.textContaining('users boom'), findsOneWidget);
  });
}
