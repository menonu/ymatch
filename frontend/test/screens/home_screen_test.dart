import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps [child] with the localization delegates so screens that call
/// `AppLocalizations.of(context)` resolve strings in widget tests.
Widget _localized(Widget child, {Locale? locale}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

/// A [AuthController] stand-in so [HomeScreen] does not trigger
/// network calls through `apiClientProvider`.
class _MockAuthController extends StateNotifier<AsyncValue<User?>>
    implements AuthController {
  _MockAuthController([User? user]) : super(AsyncValue.data(user));

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

ApiClient _failingCreateApi() {
  final config = ConfigService()..setBaseUrlForTest('http://localhost:3000');
  return ApiClient(
    config,
    client: MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/api/v1/events') {
        return http.Response('Conflict', 409);
      }
      return http.Response('[]', 200);
    }),
  );
}

/// Fails PUT rename and DELETE-by-creator paths used by the owner long-press
/// menus (#395 / #266).
ApiClient _failingEventMutationsApi() {
  final config = ConfigService()..setBaseUrlForTest('http://localhost:3000');
  return ApiClient(
    config,
    client: MockClient((request) async {
      if (request.method == 'PUT' &&
          request.url.path.startsWith('/api/v1/events/')) {
        return http.Response('Conflict', 409);
      }
      if (request.method == 'DELETE' &&
          request.url.path.startsWith('/api/v1/admin/events/')) {
        return http.Response('Forbidden', 403);
      }
      return http.Response('[]', 200);
    }),
  );
}

Event _ownedEvent() => Event()
  ..id = 42
  ..name = 'Owned Fest'
  ..creatorId = 1;

void main() {
  // The AppBar help icon watches howToHintSeenProvider, which reads
  // SharedPreferences — provide the in-memory mock so widget tests don't hit
  // the platform channel.
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'filter tab button keeps a fixed width regardless of selection (#324)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController()),
            eventsProvider.overrideWith((ref) async => <Event>[]),
          ],
          child: _localized(const HomeScreen(), locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();

      final buttonFinder = find.byType(SegmentedButton<EventFilter>);
      expect(buttonFinder, findsOneWidget);
      final widthBefore = tester.getSize(buttonFinder).width;

      // Cycle through every tab. The width must stay constant regardless of
      // which segment is selected (no check icon may be added/removed).
      for (final label in const ['Favorites', 'All Events', 'My Items']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();

        // The selected tab must not grow (e.g. by adding a check icon) and
        // the unselected tab must not shrink — width is state-independent.
        expect(
          tester.getSize(buttonFinder).width,
          equals(widthBefore),
          reason: 'width changed after selecting "$label"',
        );
      }
    },
  );

  testWidgets(
    'HomeScreen AppBar info icon opens the how-to guide sheet (#336)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController()),
            eventsProvider.overrideWith((ref) async => <Event>[]),
          ],
          child: _localized(const HomeScreen(), locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();

      // The AppBar exposes a help/info icon that opens the guide inline.
      expect(find.byTooltip('How to Trade'), findsOneWidget);
      await tester.tap(find.byTooltip('How to Trade'));
      await tester.pumpAndSettle();

      expect(find.text('How to Trade'), findsOneWidget);
      expect(
        find.text('Go to the Items tab and find your event.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'HomeScreen help icon is emphasized on first login and plain after '
    'opened (#336)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController()),
            eventsProvider.overrideWith((ref) async => <Event>[]),
          ],
          child: _localized(const HomeScreen(), locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();

      // First login ("not seen"): the help icon is emphasized with a badge.
      expect(find.byType(Badge), findsOneWidget);
      expect(find.byTooltip('How to Trade'), findsOneWidget);

      await tester.tap(find.byTooltip('How to Trade'));
      await tester.pumpAndSettle();

      // Opening the guide marks it seen → the emphasis (badge) is removed.
      expect(find.byType(Badge), findsNothing);
      expect(find.text('How to Trade'), findsOneWidget);
    },
  );

  testWidgets(
    'create event failure shows error SnackBar and keeps dialog open (#266)',
    (WidgetTester tester) async {
      final user = User()
        ..id = 1
        ..username = 'creator';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(user)),
            eventsProvider.overrideWith((ref) async => <Event>[]),
            apiClientProvider.overrideWithValue(_failingCreateApi()),
          ],
          child: _localized(const HomeScreen(), locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();

      // Open the create-event dialog via FAB.
      await tester.tap(find.text('New Event'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // Scope to the dialog TextField (SearchBar also exposes a TextField).
      final dialogField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogField, 'My Fest');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(ElevatedButton, 'Create'),
        ),
      );
      await tester.pumpAndSettle();

      // Failure must be visible; dialog must stay open (not silent success).
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Error:'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets(
    'rename event failure shows error SnackBar and keeps dialog open (#395)',
    (WidgetTester tester) async {
      final user = User()
        ..id = 1
        ..username = 'creator';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(user)),
            eventsProvider.overrideWith((ref) async => [_ownedEvent()]),
            apiClientProvider.overrideWithValue(_failingEventMutationsApi()),
          ],
          child: _localized(const HomeScreen(), locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Owned Fest'), findsOneWidget);
      await tester.longPress(find.text('Owned Fest'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit Name'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      final dialogField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogField, 'Renamed Fest');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(ElevatedButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Error:'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets(
    'delete event failure shows error SnackBar and keeps dialog open (#395)',
    (WidgetTester tester) async {
      final user = User()
        ..id = 1
        ..username = 'creator';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(user)),
            eventsProvider.overrideWith((ref) async => [_ownedEvent()]),
            apiClientProvider.overrideWithValue(_failingEventMutationsApi()),
          ],
          child: _localized(const HomeScreen(), locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Owned Fest'));
      await tester.pumpAndSettle();

      // Bottom sheet "Delete" opens the confirm dialog.
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
}
