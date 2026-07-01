// Widget tests for the merchandise long-press edit affordance (#205).
//
// #205 requires that an item's creator can edit its name AND image, and that
// non-creators never see the edit/delete menu. The creator gating already
// exists in `event_detail_screen.dart` (`isOwner`); these tests pin it and
// verify the new "Edit Item" dialog exposes a "Change Image" affordance.

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
}
