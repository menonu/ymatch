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

User _user() => User()..id = 1..username = 'me';

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
      expect(
        find.text('アイテムタブを開き、あなたのイベントを見つけます。'),
        findsOneWidget,
      );

      // Step 2 uses the in-app status terms (求 / 譲) and never the old
      // HAVE/WANT labels, which do not appear anywhere on the JA screen.
      expect(
        find.text(
          '+ と - を使って、交換したいアイテムの数を増減させます。'
          '求 / 譲 の数に応じて交換のマッチングが行われます。',
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
          'Use + and - to adjust the quantities of items you want to '
          'exchange. Matching is based on your Wish / For Trade quantities.',
        ),
        findsOneWidget,
      );

      // Stale terminology is gone in English too.
      expect(find.textContaining('HAVE'), findsNothing);
      expect(find.textContaining('WANT'), findsNothing);
      expect(find.textContaining('Events tab'), findsNothing);
    },
  );
}

class MockAuthController extends StateNotifier<AsyncValue<User?>>
    implements AuthController {
  MockAuthController(User user) : super(AsyncValue.data(user));

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
