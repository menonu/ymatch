/// Client-side app preferences (language + theme) for #545.
///
/// Stored only in [SharedPreferences] — no backend sync. Defaults follow the
/// device/browser (System) so new users keep current behavior.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLanguageKey = 'app_settings_language';
const _kThemeKey = 'app_settings_theme';

/// In-app language override. [system] leaves locale resolution to the device.
enum AppLanguagePreference {
  system,
  english,
  japanese;

  static AppLanguagePreference fromStorage(String? value) {
    switch (value) {
      case 'en':
        return AppLanguagePreference.english;
      case 'ja':
        return AppLanguagePreference.japanese;
      case 'system':
      case null:
      default:
        return AppLanguagePreference.system;
    }
  }

  String get storageValue => switch (this) {
    AppLanguagePreference.system => 'system',
    AppLanguagePreference.english => 'en',
    AppLanguagePreference.japanese => 'ja',
  };

  /// `null` means “use device locale” ([MaterialApp.locale] unset).
  Locale? get locale => switch (this) {
    AppLanguagePreference.system => null,
    AppLanguagePreference.english => const Locale('en'),
    AppLanguagePreference.japanese => const Locale('ja'),
  };
}

/// In-app theme override. [system] follows platform brightness.
enum AppThemePreference {
  system,
  light,
  dark;

  static AppThemePreference fromStorage(String? value) {
    switch (value) {
      case 'light':
        return AppThemePreference.light;
      case 'dark':
        return AppThemePreference.dark;
      case 'system':
      case null:
      default:
        return AppThemePreference.system;
    }
  }

  String get storageValue => switch (this) {
    AppThemePreference.system => 'system',
    AppThemePreference.light => 'light',
    AppThemePreference.dark => 'dark',
  };

  ThemeMode get themeMode => switch (this) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };
}

@immutable
class AppSettings {
  const AppSettings({
    this.language = AppLanguagePreference.system,
    this.theme = AppThemePreference.system,
  });

  static const defaults = AppSettings();

  final AppLanguagePreference language;
  final AppThemePreference theme;

  AppSettings copyWith({
    AppLanguagePreference? language,
    AppThemePreference? theme,
  }) {
    return AppSettings(
      language: language ?? this.language,
      theme: theme ?? this.theme,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          language == other.language &&
          theme == other.theme;

  @override
  int get hashCode => Object.hash(language, theme);

  /// Load persisted preferences (or [defaults] when unset / invalid).
  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      language: AppLanguagePreference.fromStorage(
        prefs.getString(_kLanguageKey),
      ),
      theme: AppThemePreference.fromStorage(prefs.getString(_kThemeKey)),
    );
  }
}

class AppSettingsController extends StateNotifier<AppSettings> {
  AppSettingsController({AppSettings? initial})
    : super(initial ?? AppSettings.defaults);

  Future<void> setLanguage(AppLanguagePreference language) async {
    if (state.language == language) return;
    state = state.copyWith(language: language);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLanguageKey, language.storageValue);
  }

  Future<void> setTheme(AppThemePreference theme) async {
    if (state.theme == theme) return;
    state = state.copyWith(theme: theme);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeKey, theme.storageValue);
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsController, AppSettings>(
      (ref) => AppSettingsController(),
    );
