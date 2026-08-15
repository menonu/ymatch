// Widget tests for AppSettingsSection (#545, theme removed #553, push #179, #562).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/main.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/screens/settings_screen.dart';
import 'package:frontend/theme/app_theme.dart';

WebPushController _fixedPush(Ref ref, WebPushState state) {
  final c = WebPushController(ref, autoRefresh: false);
  c.debugSetState(state);
  return c;
}

Widget _app({
  required Widget child,
  List<Override> overrides = const [],
  Locale? locale,
}) {
  return ProviderScope(
    overrides: overrides,
    child: Consumer(
      builder: (context, ref, _) {
        final settings = ref.watch(appSettingsProvider);
        return MaterialApp(
          locale: locale ?? settings.language.locale,
          theme: AppTheme.lightTheme,
          themeMode: ThemeMode.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        );
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('shows language section with System selected (no theme UI)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsController(initial: AppSettings.defaults),
          ),
          webPushProvider.overrideWith(
            (ref) => _fixedPush(
              ref,
              const WebPushState(status: WebPushUiStatus.unsupported),
            ),
          ),
        ],
        child: const AppSettingsSection(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Theme'), findsNothing);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('日本語'), findsOneWidget);
    expect(find.text('Light'), findsNothing);
    expect(find.text('Dark'), findsNothing);
    expect(find.text('Match notifications'), findsWidgets);
    expect(find.text('Not available in this browser'), findsOneWidget);
  });

  testWidgets('selecting Japanese updates provider and localizes UI', (
    tester,
  ) async {
    final controller = AppSettingsController(initial: AppSettings.defaults);
    await tester.pumpWidget(
      _app(
        overrides: [
          appSettingsProvider.overrideWith((ref) => controller),
          webPushProvider.overrideWith(
            (ref) => _fixedPush(
              ref,
              const WebPushState(status: WebPushUiStatus.unsupported),
            ),
          ),
        ],
        child: const AppSettingsSection(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('日本語'));
    await tester.pumpAndSettle();

    expect(controller.state.language, AppLanguagePreference.japanese);
    // Screen strings switch to JA once MaterialApp.locale updates.
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('言語'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_settings_language'), 'ja');
  });

  testWidgets('restored initial language shows as selected', (tester) async {
    await tester.pumpWidget(
      _app(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsController(
              initial: const AppSettings(
                language: AppLanguagePreference.english,
              ),
            ),
          ),
          webPushProvider.overrideWith(
            (ref) => _fixedPush(
              ref,
              const WebPushState(status: WebPushUiStatus.unsupported),
            ),
          ),
        ],
        child: const AppSettingsSection(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('English'), findsOneWidget);

    final languageButton = tester
        .widget<SegmentedButton<AppLanguagePreference>>(
          find.byType(SegmentedButton<AppLanguagePreference>),
        );
    expect(languageButton.selected, {AppLanguagePreference.english});
  });

  testWidgets(
    'MyApp forces ThemeMode.light even when platform is dark (#553)',
    (tester) async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsProvider.overrideWith(
              (ref) => AppSettingsController(initial: AppSettings.defaults),
            ),
          ],
          child: const MyApp(),
        ),
      );
      // One frame is enough to build MaterialApp; avoid pumpAndSettle (auth
      // checkLogin / redirects may keep scheduling frames).
      await tester.pump();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.light);
      expect(
        tester.binding.platformDispatcher.platformBrightness,
        Brightness.dark,
      );
    },
  );
}
