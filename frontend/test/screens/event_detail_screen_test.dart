// Widget tests for the merchandise long-press edit affordance (#205).
//
// #205 requires that an item's creator can edit its name AND image, and that
// non-creators never see the edit/delete menu. The creator gating already
// exists in `event_detail_screen.dart` (`isOwner`); these tests pin it and
// verify the new "Edit Item" dialog exposes a "Change Image" affordance.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/screens/event_detail_screen.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps [child] with the localization delegates so screens that call
/// `AppLocalizations.of(context)` resolve strings in widget tests.
Widget _localized(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

User _user() => User()
  ..id = 1
  ..username = 'me';

Merchandise _merch({required int creatorId}) => Merchandise()
  ..id = 10
  ..eventId = 5
  ..name = 'TestPen42'
  ..groupName = 'Pens'
  ..creatorId = creatorId;

MerchandiseGroup _testGroup({
  required String name,
  String? displayName,
  String? description,
  int? createdBy,
  String? photoUrl,
}) {
  final g = MerchandiseGroup()
    ..id = 1
    ..eventId = 5
    ..groupName = name;
  if (displayName != null) g.displayName = displayName;
  if (description != null) g.description = description;
  if (createdBy != null) g.createdBy = createdBy;
  if (photoUrl != null) g.photoUrl = photoUrl;
  return g;
}

/// An [ApiClient] whose backing [http.Client] returns an empty JSON array for
/// any GET. This keeps `inventoryProvider` and `favoriteGroupsProvider` (which
/// both build via `client.get`) from hitting the network. `merchProvider` is
/// overridden directly with the test item, so it never reaches this client.
ApiClient _emptyGetClient() {
  final config = ConfigService()..setBaseUrlForTest('http://localhost:3000');
  return ApiClient(
    config,
    client: MockClient((request) async => http.Response('[]', 200)),
  );
}

/// Fails creator-scoped merch DELETE while keeping GETs happy for other
/// providers that still hit the network (#395 / #266).
ApiClient _failingDeleteMerchClient() {
  final config = ConfigService()..setBaseUrlForTest('http://localhost:3000');
  return ApiClient(
    config,
    client: MockClient((request) async {
      if (request.method == 'DELETE' && request.url.path.contains('/merch/')) {
        return http.Response('Forbidden', 403);
      }
      return http.Response('[]', 200);
    }),
  );
}

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
  // The AppBar help icon watches howToHintSeenProvider, which reads
  // SharedPreferences — provide the in-memory mock so widget tests don't hit
  // the platform channel.
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'creator long-press shows the Edit Item menu and a Change Image dialog '
    '(#205)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith((ref) => _emptyGetClient()),
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            merchProvider(
              5,
            ).overrideWith((ref) async => [_merch(creatorId: 1)]),
          ],
          child: _localized(const EventDetailScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      // The item card shows the item name; long-press it to open the menu.
      expect(find.text('TestPen42'), findsOneWidget);
      await tester.longPress(find.text('TestPen42'));
      await tester.pumpAndSettle();

      // The bottom sheet offers "Edit Item" (and "Delete").
      expect(find.text('Edit Item'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // Open the edit dialog.
      await tester.tap(find.text('Edit Item'));
      await tester.pumpAndSettle();

      // The dialog exposes a "Change Image" affordance (#205) and a name
      // field seeded with the current item name. Scope to the AlertDialog so
      // the screen's "Search items..." field does not interfere.
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('Change Image')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.byType(TextField)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('TestPen42')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'non-creator long-press does not show the edit/delete menu (#205)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith((ref) => _emptyGetClient()),
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            // Item owned by a different creator (id=2); current user is id=1.
            merchProvider(
              5,
            ).overrideWith((ref) async => [_merch(creatorId: 2)]),
          ],
          child: _localized(const EventDetailScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TestPen42'), findsOneWidget);
      await tester.longPress(find.text('TestPen42'));
      await tester.pumpAndSettle();

      // No edit/delete menu appears for a non-creator.
      expect(find.text('Edit Item'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    },
  );

  testWidgets(
    'EventDetailScreen AppBar help icon opens the how-to guide sheet (#336)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith((ref) => _emptyGetClient()),
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            // Non-empty merch so the main AppBar (with the help icon) renders.
            merchProvider(
              5,
            ).overrideWith((ref) async => [_merch(creatorId: 1)]),
          ],
          child: _localized(const EventDetailScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('How to Trade'), findsOneWidget);
      await tester.tap(find.byTooltip('How to Trade'));
      await tester.pumpAndSettle();

      // The shared how-to guide sheet is shown.
      expect(find.text('How to Trade'), findsOneWidget);
      expect(
        find.text('Go to the Items tab and find your event.'),
        findsOneWidget,
      );
    },
  );

  // --- Add Merch button gate (#366) ---
  // The FAB is shown only when the caller's `my-role` says they can create
  // merch, so non-editors no longer see a button that 403s on tap. The backend
  // 403 remains the defense-in-depth backstop on the (now-hidden) tap path.

  testWidgets(
    'Add Merch button is shown when the caller can create merch (#366)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith((ref) => _emptyGetClient()),
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            merchProvider(
              5,
            ).overrideWith((ref) async => [_merch(creatorId: 1)]),
            myEventRoleProvider(5).overrideWith(
              (ref) async => MyEventRoleResponse()..canCreateMerch = true,
            ),
          ],
          child: _localized(const EventDetailScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      // Info icon is always present (#128); Add Merch is the gated one.
      expect(find.byIcon(Icons.add_photo_alternate), findsOneWidget);
      expect(find.byTooltip('Group info'), findsOneWidget);
    },
  );

  testWidgets(
    'Add Merch button is hidden when the caller cannot create merch (#366)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith((ref) => _emptyGetClient()),
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            merchProvider(
              5,
            ).overrideWith((ref) async => [_merch(creatorId: 1)]),
            myEventRoleProvider(5).overrideWith(
              (ref) async => MyEventRoleResponse()..canCreateMerch = false,
            ),
          ],
          child: _localized(const EventDetailScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_photo_alternate), findsNothing);
      // Group info icon still available for any signed-in visitor (#128).
      expect(find.byTooltip('Group info'), findsOneWidget);
    },
  );

  // --- Self-service member management (#442) ---

  testWidgets('Manage members button shown when canManageEditors (#442)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith((ref) => _emptyGetClient()),
          authProvider.overrideWith((ref) => _MockAuthController(_user())),
          merchProvider(5).overrideWith((ref) async => [_merch(creatorId: 1)]),
          myEventRoleProvider(5).overrideWith(
            (ref) async => MyEventRoleResponse()
              ..canCreateMerch = true
              ..canManageEditors = true
              ..canTransferCreator = false,
          ),
        ],
        child: _localized(const EventDetailScreen(eventId: 5)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manage_members_button')), findsOneWidget);
    expect(find.byTooltip('Manage members'), findsOneWidget);
  });

  testWidgets('Manage members button shown when canTransferCreator (#442)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith((ref) => _emptyGetClient()),
          authProvider.overrideWith((ref) => _MockAuthController(_user())),
          merchProvider(5).overrideWith((ref) async => [_merch(creatorId: 1)]),
          myEventRoleProvider(5).overrideWith(
            (ref) async => MyEventRoleResponse()
              ..canCreateMerch = true
              ..canManageEditors = false
              ..canTransferCreator = true,
          ),
        ],
        child: _localized(const EventDetailScreen(eventId: 5)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manage_members_button')), findsOneWidget);
  });

  testWidgets('Manage members button hidden for plain viewer (#442)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith((ref) => _emptyGetClient()),
          authProvider.overrideWith((ref) => _MockAuthController(_user())),
          merchProvider(5).overrideWith((ref) async => [_merch(creatorId: 1)]),
          myEventRoleProvider(5).overrideWith(
            (ref) async => MyEventRoleResponse()
              ..canCreateMerch = false
              ..canManageEditors = false
              ..canTransferCreator = false,
          ),
        ],
        child: _localized(const EventDetailScreen(eventId: 5)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manage_members_button')), findsNothing);
  });

  // --- Group description UI (#128) ---

  testWidgets(
    'Info button toggles the group description panel for the active tab (#128)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith((ref) => _emptyGetClient()),
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            merchProvider(
              5,
            ).overrideWith((ref) async => [_merch(creatorId: 1)]),
            eventGroupsProvider(5).overrideWith(
              (ref) async => [
                _testGroup(
                  name: 'Pens',
                  description: 'Collectible pens',
                  createdBy: 1,
                ),
              ],
            ),
          ],
          child: _localized(const EventDetailScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      // Panel closed by default.
      expect(find.text('Collectible pens'), findsNothing);

      await tester.tap(find.byTooltip('Group info'));
      await tester.pumpAndSettle();

      // Panel shows the active group name + description.
      // Group name appears in the tab AND the panel.
      expect(find.text('Pens'), findsWidgets);
      expect(find.text('Collectible pens'), findsOneWidget);

      // Toggle closed again.
      await tester.tap(find.byTooltip('Group info'));
      await tester.pumpAndSettle();
      expect(find.text('Collectible pens'), findsNothing);
    },
  );

  testWidgets('Info panel shows description image below the text (#404)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith((ref) => _emptyGetClient()),
          authProvider.overrideWith((ref) => _MockAuthController(_user())),
          merchProvider(5).overrideWith((ref) async => [_merch(creatorId: 1)]),
          eventGroupsProvider(5).overrideWith(
            (ref) async => [
              _testGroup(
                name: 'Pens',
                description: 'Collectible pens',
                createdBy: 1,
                // data URI avoids network Image.network in tests
                photoUrl:
                    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
              ),
            ],
          ),
        ],
        child: _localized(const EventDetailScreen(eventId: 5)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Group info'));
    await tester.pumpAndSettle();

    expect(find.text('Collectible pens'), findsOneWidget);
    // Image.memory is used for data-URI photos.
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('group edit dialog shows image attach controls (#404)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith((ref) => _emptyGetClient()),
          authProvider.overrideWith((ref) => _MockAuthController(_user())),
          merchProvider(5).overrideWith((ref) async => [_merch(creatorId: 1)]),
          eventGroupsProvider(5).overrideWith(
            (ref) async => [
              _testGroup(
                name: 'Pens',
                description: 'Collectible pens',
                createdBy: 1,
              ),
            ],
          ),
        ],
        child: _localized(const EventDetailScreen(eventId: 5)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit Group'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('Description image')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Choose Image')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('No image attached')),
      findsOneWidget,
    );
  });

  testWidgets(
    'group creator sees bottom edit icon (not on tabs) and can open the '
    'edit dialog (#128)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith((ref) => _emptyGetClient()),
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            merchProvider(
              5,
            ).overrideWith((ref) async => [_merch(creatorId: 1)]),
            eventGroupsProvider(5).overrideWith(
              (ref) async => [
                _testGroup(
                  name: 'Pens',
                  description: 'Collectible pens',
                  createdBy: 1,
                ),
              ],
            ),
          ],
          child: _localized(const EventDetailScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      // No shield / edit on the tab bar — only the bottom edit control.
      expect(find.byIcon(Icons.shield), findsNothing);
      expect(find.byTooltip('Edit Group'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit Group'));
      await tester.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('Edit Group')),
        findsOneWidget,
      );
      // Description field seeded with the current value.
      expect(
        find.descendant(of: dialog, matching: find.text('Collectible pens')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'non-creator does not see group edit icons on EventDetailScreen (#128)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith((ref) => _emptyGetClient()),
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            merchProvider(
              5,
            ).overrideWith((ref) async => [_merch(creatorId: 2)]),
            eventGroupsProvider(5).overrideWith(
              (ref) async => [
                _testGroup(
                  name: 'Pens',
                  description: 'Collectible pens',
                  createdBy: 99, // someone else
                ),
              ],
            ),
          ],
          child: _localized(const EventDetailScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.shield), findsNothing);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byTooltip('Edit Group'), findsNothing);

      // Info panel is still readable, without an edit affordance.
      await tester.tap(find.byTooltip('Group info'));
      await tester.pumpAndSettle();
      expect(find.text('Collectible pens'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    },
  );

  testWidgets(
    'delete merch failure shows error SnackBar and keeps dialog open (#395)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith(
              (ref) => _failingDeleteMerchClient(),
            ),
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            merchProvider(
              5,
            ).overrideWith((ref) async => [_merch(creatorId: 1)]),
          ],
          child: _localized(const EventDetailScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('TestPen42'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(ElevatedButton, 'Delete'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Error:'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets('initialGroupName selects the matching group tab (#406)', (
    tester,
  ) async {
    final alpha = Merchandise()
      ..id = 1
      ..eventId = 5
      ..name = 'AlphaItem'
      ..groupName = 'Alpha'
      ..creatorId = 1;
    final zeta = Merchandise()
      ..id = 2
      ..eventId = 5
      ..name = 'ZetaItem'
      ..groupName = 'Zeta'
      ..creatorId = 1;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith((ref) => _emptyGetClient()),
          authProvider.overrideWith((ref) => _MockAuthController(_user())),
          merchProvider(5).overrideWith((ref) async => [alpha, zeta]),
        ],
        child: _localized(
          const EventDetailScreen(eventId: 5, initialGroupName: 'Zeta'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Natural sort puts Alpha before Zeta; favorite-group deep link must
    // open Zeta (index 1), not the default first tab.
    final tabCtrl = DefaultTabController.of(
      tester.element(find.byType(TabBar)),
    );
    expect(tabCtrl.index, 1);
    expect(find.text('ZetaItem'), findsOneWidget);
    expect(find.text('AlphaItem'), findsNothing);
  });

  testWidgets('unknown initialGroupName falls back to first group tab (#406)', (
    tester,
  ) async {
    final alpha = Merchandise()
      ..id = 1
      ..eventId = 5
      ..name = 'AlphaItem'
      ..groupName = 'Alpha'
      ..creatorId = 1;
    final zeta = Merchandise()
      ..id = 2
      ..eventId = 5
      ..name = 'ZetaItem'
      ..groupName = 'Zeta'
      ..creatorId = 1;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith((ref) => _emptyGetClient()),
          authProvider.overrideWith((ref) => _MockAuthController(_user())),
          merchProvider(5).overrideWith((ref) async => [alpha, zeta]),
        ],
        child: _localized(
          const EventDetailScreen(eventId: 5, initialGroupName: 'DoesNotExist'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tabCtrl = DefaultTabController.of(
      tester.element(find.byType(TabBar)),
    );
    expect(tabCtrl.index, 0);
    expect(find.text('AlphaItem'), findsOneWidget);
  });

  test('resolveInitialGroupTabIndex maps name or falls back (#406)', () {
    expect(resolveInitialGroupTabIndex(['A', 'B'], 'B'), 1);
    expect(resolveInitialGroupTabIndex(['A', 'B'], 'missing'), 0);
    expect(resolveInitialGroupTabIndex(['A', 'B'], null), 0);
    expect(resolveInitialGroupTabIndex(['A', 'B'], ''), 0);
    expect(resolveInitialGroupTabIndex([], 'B'), 0);
  });

  // --- Inventory stepper −/+ glyph hit targets (#408) ---
  // Decorative − / + Text sits above the half-area GestureDetectors. Without
  // IgnorePointer, taps on those glyphs are absorbed and never reach the
  // detectors. These tests tap the glyph Text widgets themselves.

  testWidgets(
    'tapping the decorative + glyph on the detailed stepper increments inventory (#408)',
    (tester) async {
      final inventoryPosts = <Map<String, dynamic>>[];
      final config = ConfigService()
        ..setBaseUrlForTest('http://localhost:3000');
      final client = ApiClient(
        config,
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/user/inventory') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            inventoryPosts.add(body);
            return http.Response(
              jsonEncode({
                'id': inventoryPosts.length,
                'userId': body['userId'],
                'merchId': body['merchId'],
                'status': body['status'],
                'quantity': body['quantity'],
                'merchName': '',
              }),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith((ref) => client),
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            merchProvider(
              5,
            ).overrideWith((ref) async => [_merch(creatorId: 1)]),
          ],
          child: _localized(const EventDetailScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      // Detailed view shows three steppers (HAVE / WANT / TRADE), each with a +
      // hint glyph. Tap at the first (+) center — the HAVE stepper. Use
      // tapAt so the hit lands on the glyph position even when the Text is
      // IgnorePointer (the bug is that hits at that offset must reach the
      // half-area GestureDetector beneath).
      expect(find.text('+'), findsNWidgets(3));
      await tester.tapAt(tester.getCenter(find.text('+').first));
      await tester.pumpAndSettle();

      expect(
        inventoryPosts,
        isNotEmpty,
        reason: 'tap on + glyph must reach the increase GestureDetector',
      );
      expect(inventoryPosts.first['status'], 'HAVE');
      expect(inventoryPosts.first['quantity'], 1);
      expect(inventoryPosts.first['merchId'], 10);
    },
  );

  testWidgets(
    'tapping the decorative − glyph on the detailed stepper decrements inventory (#408)',
    (tester) async {
      final inventoryPosts = <Map<String, dynamic>>[];
      final config = ConfigService()
        ..setBaseUrlForTest('http://localhost:3000');
      final client = ApiClient(
        config,
        client: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/user/1/inventory') {
            // Seed HAVE=1 so the decrease path is active.
            return http.Response(
              jsonEncode([
                {
                  'id': 1,
                  'userId': 1,
                  'merchId': 10,
                  'status': 'HAVE',
                  'quantity': 1,
                  'merchName': 'TestPen42',
                },
              ]),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/user/inventory') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            inventoryPosts.add(body);
            return http.Response(
              jsonEncode({
                'id': 1,
                'userId': body['userId'],
                'merchId': body['merchId'],
                'status': body['status'],
                'quantity': body['quantity'],
                'merchName': '',
              }),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith((ref) => client),
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            merchProvider(
              5,
            ).overrideWith((ref) async => [_merch(creatorId: 1)]),
          ],
          child: _localized(const EventDetailScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      // Unicode minus (U+2212), not ASCII hyphen — matches _buildStepper.
      expect(find.text('−'), findsNWidgets(3));
      await tester.tapAt(tester.getCenter(find.text('−').first));
      await tester.pumpAndSettle();

      expect(
        inventoryPosts,
        isNotEmpty,
        reason: 'tap on − glyph must reach the decrease GestureDetector',
      );
      expect(inventoryPosts.first['status'], 'HAVE');
      expect(inventoryPosts.first['quantity'], 0);
      expect(inventoryPosts.first['merchId'], 10);
    },
  );

  // --- Group display name + edit-button gating (#425) ---

  testWidgets(
    'non-creator with canEditGroup sees the bottom edit icon (#425)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith((ref) => _emptyGetClient()),
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            merchProvider(
              5,
            ).overrideWith((ref) async => [_merch(creatorId: 2)]),
            eventGroupsProvider(5).overrideWith(
              (ref) async => [
                _testGroup(
                  name: 'Pens',
                  description: 'Collectible pens',
                  createdBy: 99, // not the current user (id=1)
                ),
              ],
            ),
            myEventRoleProvider(5).overrideWith(
              (ref) async => MyEventRoleResponse()..canEditGroup = true,
            ),
          ],
          child: _localized(const EventDetailScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      // The edit button appears even though the viewer is not the creator —
      // the backend authorizes editors/mods/admin via `group.edit`.
      expect(find.byTooltip('Edit Group'), findsOneWidget);
    },
  );

  testWidgets(
    'non-creator without canEditGroup still sees no edit icon (#425)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith((ref) => _emptyGetClient()),
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            merchProvider(
              5,
            ).overrideWith((ref) async => [_merch(creatorId: 2)]),
            eventGroupsProvider(5).overrideWith(
              (ref) async => [
                _testGroup(
                  name: 'Pens',
                  description: 'Collectible pens',
                  createdBy: 99,
                ),
              ],
            ),
            myEventRoleProvider(5).overrideWith(
              (ref) async => MyEventRoleResponse()..canEditGroup = false,
            ),
          ],
          child: _localized(const EventDetailScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Edit Group'), findsNothing);
    },
  );

  testWidgets(
    'edit dialog shows an editable name field seeded with the display name '
    '(#425)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWith((ref) => _emptyGetClient()),
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            merchProvider(
              5,
            ).overrideWith((ref) async => [_merch(creatorId: 1)]),
            eventGroupsProvider(5).overrideWith(
              (ref) async => [
                _testGroup(
                  name: 'Pens',
                  displayName: 'Enamel Pins!',
                  description: 'Collectible pens',
                  createdBy: 1,
                ),
              ],
            ),
          ],
          child: _localized(const EventDetailScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      // The tab / panel show the display name, not the internal key.
      expect(find.text('Enamel Pins!'), findsWidgets);
      expect(find.text('Pens'), findsNothing);

      await tester.tap(find.byTooltip('Edit Group'));
      await tester.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      // The name field is editable (a TextField) and seeded with the display
      // name. The dialog now has two TextFields (name + description).
      final nameFields = find.descendant(
        of: dialog,
        matching: find.byType(TextField),
      );
      expect(nameFields, findsNWidgets(2));
      expect(
        find.descendant(of: dialog, matching: find.text('Enamel Pins!')),
        findsOneWidget,
      );
    },
  );

  test('groupDisplayName uses display_name when set, else the key (#425)', () {
    final byName = <String, MerchandiseGroup>{
      'Pens': _testGroup(name: 'Pens', displayName: 'Enamel Pins!'),
      'Stickers': _testGroup(name: 'Stickers'),
    };
    expect(groupDisplayName('Pens', byName), 'Enamel Pins!');
    // Unset display_name falls back to the key.
    expect(groupDisplayName('Stickers', byName), 'Stickers');
    // Unknown key falls back to itself.
    expect(groupDisplayName('Nope', byName), 'Nope');
    // Empty display_name falls back to the key.
    final empty = <String, MerchandiseGroup>{
      'Bad': _testGroup(name: 'Bad', displayName: ''),
    };
    expect(groupDisplayName('Bad', empty), 'Bad');
  });

  // Regression for the 0.3.13 export-from-3-dots-menu wiring: the menu's
  // onSelected called DefaultTabController.of on the State's build context,
  // which is the controller's *parent* — the lookup threw at runtime and the
  // export dialog never opened ("在庫エクスポート doesn't show anything").
  testWidgets('3-dots export menu opens the export dialog for the active group '
      '(#418 regression)', (tester) async {
    final config = ConfigService()..setBaseUrlForTest('http://localhost:3000');
    final invJson = jsonEncode([
      {
        'merchId': 10,
        'status': 'HAVE',
        'quantity': 2,
        'merchName': 'TestPen42',
        'groupName': 'Pens',
      },
    ]);
    final client = ApiClient(
      config,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/user/1/inventory')) {
          return http.Response(invJson, 200);
        }
        return http.Response('[]', 200);
      }),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith((ref) => client),
          authProvider.overrideWith((ref) => _MockAuthController(_user())),
          merchProvider(5).overrideWith((ref) async => [_merch(creatorId: 2)]),
        ],
        child: _localized(const EventDetailScreen(eventId: 5)),
      ),
    );
    await tester.pumpAndSettle();

    // Open the 3-dots overflow menu (the only PopupMenuButton<String>).
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    // The "Export inventory" item is present; tap it.
    expect(find.text('Export inventory'), findsOneWidget);
    await tester.tap(find.text('Export inventory'));
    await tester.pumpAndSettle();

    // The dialog opened with the active group's name in the title. This only
    // happens if DefaultTabController.of resolved from a context under the
    // controller and the active tab's group name was read successfully.
    expect(find.text('Export inventory — Pens'), findsOneWidget);

    // And the preview renders the user's inventory for that group.
    final preview = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(preview.data, 'Own: TestPen42*2');
  });
}
