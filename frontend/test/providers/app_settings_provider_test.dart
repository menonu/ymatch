// Unit tests for app settings prefs (#545).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/providers/app_settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('AppLanguagePreference', () {
    test('fromStorage maps known values and falls back to system', () {
      expect(
        AppLanguagePreference.fromStorage(null),
        AppLanguagePreference.system,
      );
      expect(
        AppLanguagePreference.fromStorage('system'),
        AppLanguagePreference.system,
      );
      expect(
        AppLanguagePreference.fromStorage('en'),
        AppLanguagePreference.english,
      );
      expect(
        AppLanguagePreference.fromStorage('ja'),
        AppLanguagePreference.japanese,
      );
      expect(
        AppLanguagePreference.fromStorage('fr'),
        AppLanguagePreference.system,
      );
    });

    test('locale is null for system, en/ja otherwise', () {
      expect(AppLanguagePreference.system.locale, isNull);
      expect(AppLanguagePreference.english.locale, const Locale('en'));
      expect(AppLanguagePreference.japanese.locale, const Locale('ja'));
    });

    test('storageValue round-trips through fromStorage', () {
      for (final pref in AppLanguagePreference.values) {
        expect(AppLanguagePreference.fromStorage(pref.storageValue), pref);
      }
    });
  });

  group('AppThemePreference', () {
    test('fromStorage maps known values and falls back to system', () {
      expect(AppThemePreference.fromStorage(null), AppThemePreference.system);
      expect(AppThemePreference.fromStorage('light'), AppThemePreference.light);
      expect(AppThemePreference.fromStorage('dark'), AppThemePreference.dark);
      expect(AppThemePreference.fromStorage('nope'), AppThemePreference.system);
    });

    test('themeMode maps to Flutter ThemeMode', () {
      expect(AppThemePreference.system.themeMode, ThemeMode.system);
      expect(AppThemePreference.light.themeMode, ThemeMode.light);
      expect(AppThemePreference.dark.themeMode, ThemeMode.dark);
    });

    test('storageValue round-trips through fromStorage', () {
      for (final pref in AppThemePreference.values) {
        expect(AppThemePreference.fromStorage(pref.storageValue), pref);
      }
    });
  });

  group('AppSettings.load', () {
    test('returns defaults when prefs are empty', () async {
      final settings = await AppSettings.load();
      expect(settings, AppSettings.defaults);
      expect(settings.language, AppLanguagePreference.system);
      expect(settings.theme, AppThemePreference.system);
    });

    test('restores persisted language and theme', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_settings_language': 'ja',
        'app_settings_theme': 'dark',
      });
      final settings = await AppSettings.load();
      expect(settings.language, AppLanguagePreference.japanese);
      expect(settings.theme, AppThemePreference.dark);
    });
  });

  group('AppSettingsController', () {
    test('starts with defaults or injected initial', () {
      final empty = AppSettingsController();
      expect(empty.state, AppSettings.defaults);

      final seeded = AppSettingsController(
        initial: const AppSettings(
          language: AppLanguagePreference.english,
          theme: AppThemePreference.light,
        ),
      );
      expect(seeded.state.language, AppLanguagePreference.english);
      expect(seeded.state.theme, AppThemePreference.light);
    });

    test('setLanguage updates state and persists', () async {
      final controller = AppSettingsController();
      await controller.setLanguage(AppLanguagePreference.japanese);
      expect(controller.state.language, AppLanguagePreference.japanese);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_settings_language'), 'ja');

      // Re-load reflects the write.
      final reloaded = await AppSettings.load();
      expect(reloaded.language, AppLanguagePreference.japanese);
    });

    test('setTheme updates state and persists', () async {
      final controller = AppSettingsController();
      await controller.setTheme(AppThemePreference.dark);
      expect(controller.state.theme, AppThemePreference.dark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_settings_theme'), 'dark');

      final reloaded = await AppSettings.load();
      expect(reloaded.theme, AppThemePreference.dark);
    });

    test('setLanguage no-ops when value unchanged (still ok)', () async {
      final controller = AppSettingsController(
        initial: const AppSettings(language: AppLanguagePreference.english),
      );
      await controller.setLanguage(AppLanguagePreference.english);
      // Did not write when already english — prefs stay empty.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_settings_language'), isNull);
    });

    test('provider exposes controller state', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsController(
              initial: const AppSettings(theme: AppThemePreference.light),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(appSettingsProvider).theme,
        AppThemePreference.light,
      );
      await container
          .read(appSettingsProvider.notifier)
          .setTheme(AppThemePreference.dark);
      expect(
        container.read(appSettingsProvider).theme,
        AppThemePreference.dark,
      );
    });
  });
}
