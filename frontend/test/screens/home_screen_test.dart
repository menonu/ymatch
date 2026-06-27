import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/screens/home_screen.dart';

/// Wraps [child] with the localization delegates so screens that call
/// `AppLocalizations.of(context)` resolve strings in widget tests.
Widget _localized(Widget child, {Locale? locale}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

/// A signed-out [AuthController] stand-in so [HomeScreen] does not trigger
/// network calls through `apiClientProvider`.
class _MockAuthController extends StateNotifier<AsyncValue<User?>>
    implements AuthController {
  _MockAuthController() : super(const AsyncValue.data(null));

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
  // ignore: TODO
  get client => throw UnimplementedError();
}

void main() {
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

      // Select the "Favorites" tab and let the segmented button re-layout.
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();

      final widthAfter = tester.getSize(buttonFinder).width;

      // The selected tab must not grow (e.g. by adding a check icon) and
      // the unselected tab must not shrink — width is state-independent.
      expect(widthAfter, equals(widthBefore));
    },
  );
}