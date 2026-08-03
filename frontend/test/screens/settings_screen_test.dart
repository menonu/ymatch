// Widget tests for SettingsScreen (#545).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/screens/settings_screen.dart';
import 'package:frontend/theme/app_theme.dart';

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
          darkTheme: AppTheme.darkTheme,
          themeMode: settings.theme.themeMode,
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

  testWidgets('shows language and theme sections with System selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsController(initial: AppSettings.defaults),
          ),
        ],
        child: const SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    // Two "System" segments (language + theme).
    expect(find.text('System'), findsNWidgets(2));
    expect(find.text('English'), findsOneWidget);
    expect(find.text('日本語'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
  });

  testWidgets('selecting Japanese updates provider and localizes UI', (
    tester,
  ) async {
    final controller = AppSettingsController(initial: AppSettings.defaults);
    await tester.pumpWidget(
      _app(
        overrides: [appSettingsProvider.overrideWith((ref) => controller)],
        child: const SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('日本語'));
    await tester.pumpAndSettle();

    expect(controller.state.language, AppLanguagePreference.japanese);
    // Screen strings switch to JA once MaterialApp.locale updates.
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('言語'), findsOneWidget);
    expect(find.text('テーマ'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_settings_language'), 'ja');
  });

  testWidgets('selecting Dark updates provider and ThemeMode', (tester) async {
    final controller = AppSettingsController(initial: AppSettings.defaults);
    await tester.pumpWidget(
      _app(
        overrides: [appSettingsProvider.overrideWith((ref) => controller)],
        child: const SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(controller.state.theme, AppThemePreference.dark);
    expect(controller.state.theme.themeMode, ThemeMode.dark);

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.dark);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_settings_theme'), 'dark');
  });

  testWidgets('restored initial prefs show as selected', (tester) async {
    await tester.pumpWidget(
      _app(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsController(
              initial: const AppSettings(
                language: AppLanguagePreference.english,
                theme: AppThemePreference.light,
              ),
            ),
          ),
        ],
        child: const SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // English/Light segments are present; system is not exclusively selected.
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);

    final languageButton = tester
        .widget<SegmentedButton<AppLanguagePreference>>(
          find.byType(SegmentedButton<AppLanguagePreference>),
        );
    expect(languageButton.selected, {AppLanguagePreference.english});

    final themeButton = tester.widget<SegmentedButton<AppThemePreference>>(
      find.byType(SegmentedButton<AppThemePreference>),
    );
    expect(themeButton.selected, {AppThemePreference.light});
  });
}
