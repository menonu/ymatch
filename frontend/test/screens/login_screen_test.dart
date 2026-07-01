import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/models/models.dart';

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
    'LoginScreen shows a how-to preview pointing at the Profile tab (#336)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authProvider.overrideWith((ref) => MockAuthController())],
          child: _localized(const LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // The virtual "Profile" tab preview + hint are rendered for new users.
      expect(find.byKey(const ValueKey('howToPreviewButton')), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      // The guide sheet is not open yet.
      expect(find.text('How to Trade'), findsNothing);
    },
  );

  testWidgets(
    'LoginScreen how-to preview opens the guide sheet when tapped (#336)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authProvider.overrideWith((ref) => MockAuthController())],
          child: _localized(const LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('howToPreviewButton')));
      await tester.pumpAndSettle();

      // The shared how-to guide content is shown without logging in.
      expect(find.text('How to Trade'), findsOneWidget);
      expect(
        find.text('Go to the Items tab and find your event.'),
        findsOneWidget,
      );
      expect(
        find.text('Go to Matches to see who wants to trade with you.'),
        findsOneWidget,
      );
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
