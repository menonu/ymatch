import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/widgets/how_to_trade.dart';

/// Wraps [child] with the same localization delegates [MyApp] uses so
/// screens that call `AppLocalizations.of(context)` resolve strings in
/// widget tests. Defaults to the English locale (test default).
Widget _localized(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  testWidgets(
    'LoginScreen shows guest account creation text and start button',
    (WidgetTester tester) async {
      // Provide an initial unauthenticated state
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authProvider.overrideWith((ref) => MockAuthController())],
          child: _localized(const LoginScreen()),
        ),
      );

      expect(find.text('ymatch'), findsOneWidget);
      expect(find.text('Trade merch seamlessly.'), findsOneWidget);
      expect(find.text('Start as New User'), findsOneWidget);
      expect(find.text('Restore Existing Account'), findsOneWidget);
    },
  );

  testWidgets(
    'LoginScreen tapping Restore reveals TextField and Restore button',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authProvider.overrideWith((ref) => MockAuthController())],
          child: _localized(const LoginScreen()),
        ),
      );

      // Tap the restore button
      await tester.tap(find.text('Restore Existing Account'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.text('Restore Account'),
        findsWidgets,
      ); // Can be title and button
      expect(find.text('Cancel'), findsOneWidget);
    },
  );

  testWidgets(
    'LoginScreen renders Japanese strings when the locale is ja (#207)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authProvider.overrideWith((ref) => MockAuthController())],
          child: MaterialApp(
            locale: const Locale('ja'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Japanese translations from app_ja.arb should be rendered.
      expect(find.text('ymatch'), findsOneWidget); // brand stays untranslated
      expect(find.text('グッズをスムーズに取引。'), findsOneWidget);
      expect(find.text('新規ユーザーとして開始'), findsOneWidget);
      expect(find.text('既存のアカウントを復元'), findsOneWidget);
      // English strings must NOT appear in the Japanese locale.
      expect(find.text('Start as New User'), findsNothing);
    },
  );

  testWidgets(
    'LoginScreen falls back to English for an unsupported locale (#207)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authProvider.overrideWith((ref) => MockAuthController())],
          child: MaterialApp(
            locale: const Locale('fr'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trade merch seamlessly.'), findsOneWidget);
      expect(find.text('Start as New User'), findsOneWidget);
    },
  );

  testWidgets(
    'LoginScreen shows a virtual Profile tab + long arrow pointing to it '
    '(#336)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authProvider.overrideWith((ref) => MockAuthController())],
          child: _localized(const LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Hint points the user to the Profile tab (read after login).
      expect(
        find.text(
          'The How to Trade guide is in the Profile tab — tap it after '
          'logging in to read it.',
        ),
        findsOneWidget,
      );
      // A long arrow draws the eye down toward the bottom-nav area.
      expect(find.byType(LongDownArrow), findsOneWidget);
      // The virtual Profile tab is rendered where the real nav bar will be.
      expect(find.byType(VirtualProfileTabBar), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      // The Items / Matches tabs are irrelevant here and are hidden.
      expect(find.text('Items'), findsNothing);
      expect(find.text('Matches'), findsNothing);
      // The guide itself is NOT shown on the login screen.
      expect(find.text('How to Trade'), findsNothing);
    },
  );

  testWidgets(
    'LoginScreen virtual Profile tab is disabled — tapping shows '
    '"Available after login" and does not open the guide (#336)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authProvider.overrideWith((ref) => MockAuthController())],
          child: _localized(const LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      // Tapping the virtual tab tells the user it is available after login…
      expect(find.text('Available after login'), findsOneWidget);
      // …and does NOT open the how-to guide.
      expect(find.text('How to Trade'), findsNothing);
    },
  );
}

class MockAuthController extends StateNotifier<AsyncValue<User?>>
    implements AuthController {
  MockAuthController() : super(const AsyncValue.data(null));

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
  // TODO: implement client
  get client => throw UnimplementedError();
}
