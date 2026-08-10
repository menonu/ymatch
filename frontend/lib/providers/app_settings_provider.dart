/// Client-side app preferences (language) for #545.
///
/// Theme preference was temporarily removed (#553) due to dark-mode contrast
/// issues; `AppTheme.darkTheme` remains for a future re-introduction. Stored
/// only in [SharedPreferences] — no backend sync. Language defaults follow the
/// device/browser (System).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLanguageKey = 'app_settings_language';

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

@immutable
class AppSettings {
  const AppSettings({this.language = AppLanguagePreference.system});

  static const defaults = AppSettings();

  final AppLanguagePreference language;

  AppSettings copyWith({AppLanguagePreference? language}) {
    return AppSettings(language: language ?? this.language);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings && language == other.language;

  @override
  int get hashCode => language.hashCode;

  /// Load persisted preferences (or [defaults] when unset / invalid).
  ///
  /// Legacy `app_settings_theme` keys (from #545) are ignored (#553).
  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      language: AppLanguagePreference.fromStorage(
        prefs.getString(_kLanguageKey),
      ),
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
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsController, AppSettings>(
      (ref) => AppSettingsController(),
    );
