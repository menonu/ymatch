// Unit tests for app settings prefs (#545, theme removed #553).

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

  group('AppSettings.load', () {
    test('returns defaults when prefs are empty', () async {
      final settings = await AppSettings.load();
      expect(settings, AppSettings.defaults);
      expect(settings.language, AppLanguagePreference.system);
    });

    test('restores persisted language', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_settings_language': 'ja',
      });
      final settings = await AppSettings.load();
      expect(settings.language, AppLanguagePreference.japanese);
    });

    test('ignores legacy theme pref (#553)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_settings_language': 'en',
        'app_settings_theme': 'dark',
      });
      final settings = await AppSettings.load();
      expect(
        settings,
        const AppSettings(language: AppLanguagePreference.english),
      );
    });
  });

  group('AppSettingsController', () {
    test('starts with defaults or injected initial', () {
      final empty = AppSettingsController();
      expect(empty.state, AppSettings.defaults);

      final seeded = AppSettingsController(
        initial: const AppSettings(language: AppLanguagePreference.english),
      );
      expect(seeded.state.language, AppLanguagePreference.english);
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
              initial: const AppSettings(
                language: AppLanguagePreference.english,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(appSettingsProvider).language,
        AppLanguagePreference.english,
      );
      await container
          .read(appSettingsProvider.notifier)
          .setLanguage(AppLanguagePreference.japanese);
      expect(
        container.read(appSettingsProvider).language,
        AppLanguagePreference.japanese,
      );
    });
  });
}
