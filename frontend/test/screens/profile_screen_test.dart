// Widget tests for ProfileScreen (#319, #454, #562, #570).
//
// Covers How-to-Trade copy, null-user loading, username edit success/failure,
// logout, backend revision error path, and inlined app settings.

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
    await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
    await tester.pumpAndSettle();

    expect(auth.lastUpdatedUsername, 'newname');
    expect(find.text('newname'), findsOneWidget);
    expect(find.text('Username updated'), findsOneWidget);
    // Edit mode closed.
    expect(find.widgetWithIcon(IconButton, Icons.check), findsNothing);
  });

  testWidgets(
    'username edit control stays tappable with long name on narrow viewport (#555)',
    (tester) async {
      // Phone-width surface where a long name previously shoved the edit
      // IconButton into / past the right edge (#555). With dpr=1, physical
      // size equals logical size (same pattern as home_screen_test #415).
      const screenWidth = 360.0;
      tester.view.physicalSize = const Size(screenWidth, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const longName =
          'super_long_username_that_would_push_edit_control_off_screen';
      final auth = MockAuthController(_user(username: longName));
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

      final editFinder = find.byTooltip('Edit username');
      expect(editFinder, findsOneWidget);

      final editRect = tester.getRect(editFinder);

      // Comfortable Material touch target.
      expect(editRect.width, greaterThanOrEqualTo(48));
      expect(editRect.height, greaterThanOrEqualTo(48));

      // Stay inset from the viewport edge (body 16 + card 24 padding, and
      // the control itself must not sit flush against the right edge).
      const minEdgeInset = 16.0;
      expect(editRect.left, greaterThanOrEqualTo(minEdgeInset));
      expect(screenWidth - editRect.right, greaterThanOrEqualTo(minEdgeInset));

      // Fully on-screen and actually tappable → enters edit mode.
      expect(editRect.left, greaterThanOrEqualTo(0));
      expect(editRect.right, lessThanOrEqualTo(screenWidth));
      await tester.tap(editFinder);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    },
  );

  testWidgets(
    'username edit control has comfortable hit target on phone width (#555)',
    (tester) async {
      const screenWidth = 360.0;
      tester.view.physicalSize = const Size(screenWidth, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(
              (ref) => MockAuthController(_user(username: 'alice')),
            ),
            backendSystemStatusProvider.overrideWith((ref) async => {}),
          ],
          child: _localized(const ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final editRect = tester.getRect(find.byTooltip('Edit username'));

      expect(editRect.width, greaterThanOrEqualTo(48));
      expect(editRect.height, greaterThanOrEqualTo(48));
      expect(screenWidth - editRect.right, greaterThanOrEqualTo(16));
    },
  );

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
    await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to update username:'), findsOneWidget);
    // Still in edit mode after failure (username not committed).
    expect(find.widgetWithIcon(IconButton, Icons.check), findsOneWidget);
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
    await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
    await tester.pumpAndSettle();

    expect(auth.lastUpdatedUsername, isNull);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.widgetWithIcon(IconButton, Icons.check), findsOneWidget);
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

  testWidgets('profile inlines language and notification settings (#562)', (
    tester,
  ) async {
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

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Match notifications'), findsWidgets);
    expect(find.byType(SegmentedButton<AppLanguagePreference>), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    // Nested Settings entry (list tile → /profile/settings) is gone.
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets(
    'settings sit next to the username card on a wide viewport (#562)',
    (tester) async {
      tester.view.physicalSize = const Size(880, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(
              (ref) => MockAuthController(_user(username: 'alice')),
            ),
            backendSystemStatusProvider.overrideWith((ref) async => {}),
          ],
          child: _localized(const ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final userCard = tester.getRect(
        find.byKey(const Key('profile-username-card')),
      );
      final settings = tester.getRect(
        find.byKey(const Key('app-settings-section')),
      );

      expect(settings.left, greaterThan(userCard.right - 1));
      expect(settings.top, lessThan(userCard.bottom));
    },
  );

  testWidgets(
    'settings stack below the username card on a narrow viewport (#562)',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(
              (ref) => MockAuthController(_user(username: 'alice')),
            ),
            backendSystemStatusProvider.overrideWith((ref) async => {}),
          ],
          child: _localized(const ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final userCard = tester.getRect(
        find.byKey(const Key('profile-username-card')),
      );
      final settings = tester.getRect(
        find.byKey(const Key('app-settings-section')),
      );

      expect(settings.top, greaterThan(userCard.bottom - 1));
    },
  );

  testWidgets(
    'Community card sits next to Settings on a wide viewport (#570)',
    (tester) async {
      tester.view.physicalSize = const Size(880, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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

      final settings = tester.getRect(
        find.byKey(const Key('app-settings-section')),
      );
      final community = tester.getRect(
        find.byKey(const Key('community-section')),
      );

      expect(community.left, greaterThan(settings.right - 1));
      expect(community.top, lessThan(settings.bottom));
      // Community is compact; the language control in Settings must stay usable
      // after adding the third column (#562 / #570).
      final language = tester.getRect(
        find.byType(SegmentedButton<AppLanguagePreference>),
      );
      expect(language.width, greaterThan(220));
      expect(find.text('Community'), findsOneWidget);
      // Icons only — no network name labels in the card body.
      expect(find.text('Discord'), findsNothing);
      expect(find.byKey(const Key('community-x')), findsOneWidget);
      expect(find.byKey(const Key('community-discord')), findsOneWidget);
    },
  );

  testWidgets(
    'Community card stacks below Settings on a narrow viewport (#570)',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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

      final settings = tester.getRect(
        find.byKey(const Key('app-settings-section')),
      );
      final community = tester.getRect(
        find.byKey(const Key('community-section')),
      );

      expect(community.top, greaterThan(settings.bottom - 1));
    },
  );
}
