// Widget tests for ProfileScreen (#319, #454).
//
// Covers How-to-Trade copy, null-user loading, username edit success/failure,
// logout, and backend revision error path.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/screens/profile_screen.dart';

/// Wraps [child] with the localization delegates so screens that call
/// `AppLocalizations.of(context)` resolve strings in widget tests.
Widget _localized(Widget child, {Locale? locale}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

User _user({String username = 'me', String? uuid}) {
  final u = User()
    ..id = 1
    ..username = username;
  if (uuid != null) u.uuid = uuid;
  return u;
}

class MockAuthController extends StateNotifier<AsyncValue<User?>>
    implements AuthController {
  MockAuthController(User? user) : super(AsyncValue.data(user));

  int logoutCalls = 0;
  Object? updateError;
  String? lastUpdatedUsername;

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
  void logout() {
    logoutCalls++;
    state = const AsyncValue.data(null);
  }

  @override
  Future<void> updateUsername(int userId, String newUsername) async {
    if (updateError != null) throw updateError!;
    lastUpdatedUsername = newUsername;
    final current = state.value;
    if (current == null) return;
    final updated = User()
      ..id = current.id
      ..username = newUsername;
    if (current.hasUuid()) updated.uuid = current.uuid;
    if (current.hasRole()) updated.role = current.role;
    state = AsyncValue.data(updated);
  }

  @override
  get client => throw UnimplementedError();
}

void main() {
  testWidgets(
    'How-to-Trade steps use the actual UI terms under ja locale (#319)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => MockAuthController(_user())),
            backendSystemStatusProvider.overrideWith((ref) async => {}),
          ],
          child: _localized(const ProfileScreen(), locale: const Locale('ja')),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1 references the real bottom-nav tab name (アイテム, not イベント).
      expect(find.text('アイテムタブを開き、あなたのイベントを見つけます。'), findsOneWidget);

      // Step 2 uses the in-app status terms (求 / 譲) and never the old
      // HAVE/WANT labels, which do not appear anywhere on the JA screen.
      expect(
        find.text(
          '+ と - を使って、交換したいアイテムの数を入力します。'
          '求 / 譲の数に応じて、アイテムグループ内で交換のマッチングが行われます。',
        ),
        findsOneWidget,
      );

      // The stale terms must be gone from the instructions.
      expect(find.textContaining('HAVE'), findsNothing);
      expect(find.textContaining('WANT'), findsNothing);
      expect(find.textContaining('イベントタブ'), findsNothing);
    },
  );

  testWidgets(
    'How-to-Trade steps use the actual UI terms under en locale (#319)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => MockAuthController(_user())),
            backendSystemStatusProvider.overrideWith((ref) async => {}),
          ],
          child: _localized(const ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Go to the Items tab and find your event.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Use + and - to enter the quantities of items you want to '
          'exchange. Matching is performed within an item group based on '
          'your Wish / For Trade quantities.',
        ),
        findsOneWidget,
      );

      // Stale terminology is gone in English too.
      expect(find.textContaining('HAVE'), findsNothing);
      expect(find.textContaining('WANT'), findsNothing);
      expect(find.textContaining('Events tab'), findsNothing);
    },
  );

  testWidgets('null user shows loading spinner (#454)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => MockAuthController(null)),
          backendSystemStatusProvider.overrideWith((ref) async => {}),
        ],
        child: _localized(const ProfileScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Log Out'), findsNothing);
  });

  testWidgets(
    'profile shows username, master key, logout, and revision (#454)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(
              (ref) => MockAuthController(
                _user(username: 'alice', uuid: 'uuid-abc-123'),
              ),
            ),
            backendSystemStatusProvider.overrideWith(
              (ref) async => {'backend_version': 'abcdef0123456789'},
            ),
          ],
          child: _localized(const ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('alice'), findsOneWidget);
      expect(find.text('Master Key (UUID)'), findsOneWidget);
      expect(find.text('uuid-abc-123'), findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);
      // Short hash of backend revision (first 7 chars).
      expect(find.textContaining('abcdef0'), findsOneWidget);
    },
  );

  testWidgets('backend status error path shows error in revision line (#454)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => MockAuthController(_user())),
          backendSystemStatusProvider.overrideWith((ref) async {
            throw Exception('status down');
          }),
        ],
        child: _localized(const ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('error'), findsOneWidget);
  });

  testWidgets('username edit success updates label and snackbar (#454)', (
    tester,
  ) async {
    final auth = MockAuthController(_user(username: 'oldname'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => auth),
          backendSystemStatusProvider.overrideWith((ref) async => {}),
        ],
        child: _localized(const ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit username'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'newname');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(auth.lastUpdatedUsername, 'newname');
    expect(find.text('newname'), findsOneWidget);
    expect(find.text('Username updated'), findsOneWidget);
    // Edit mode closed.
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('username edit failure shows error snackbar (#454)', (
    tester,
  ) async {
    final auth = MockAuthController(_user(username: 'oldname'))
      ..updateError = Exception('taken');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => auth),
          backendSystemStatusProvider.overrideWith((ref) async => {}),
        ],
        child: _localized(const ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit username'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'taken-name');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to update username:'), findsOneWidget);
    // Still in edit mode after failure (username not committed).
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('empty username save is a no-op (#454)', (tester) async {
    final auth = MockAuthController(_user(username: 'oldname'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => auth),
          backendSystemStatusProvider.overrideWith((ref) async => {}),
        ],
        child: _localized(const ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit username'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(auth.lastUpdatedUsername, isNull);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('Log Out calls authController.logout (#454)', (tester) async {
    final auth = MockAuthController(_user());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => auth),
          backendSystemStatusProvider.overrideWith((ref) async => {}),
        ],
        child: _localized(const ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Profile is a SingleChildScrollView; Log Out sits below How-to-Trade.
    await tester.ensureVisible(find.text('Log Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log Out'));
    await tester.pump();

    expect(auth.logoutCalls, 1);
  });
}
