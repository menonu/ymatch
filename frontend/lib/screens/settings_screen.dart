import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';

/// Client-side app preferences (language + theme) opened from Profile (#545).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.settingsLanguage,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SegmentedButton<AppLanguagePreference>(
            segments: [
              ButtonSegment(
                value: AppLanguagePreference.system,
                label: Text(l10n.settingsSystem),
                icon: const Icon(Icons.language, size: 18),
              ),
              ButtonSegment(
                value: AppLanguagePreference.english,
                label: Text(l10n.settingsLanguageEnglish),
              ),
              ButtonSegment(
                value: AppLanguagePreference.japanese,
                label: Text(l10n.settingsLanguageJapanese),
              ),
            ],
            selected: {settings.language},
            onSelectionChanged: (selected) {
              controller.setLanguage(selected.first);
            },
          ),
          const SizedBox(height: 24),
          Text(
            l10n.settingsTheme,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SegmentedButton<AppThemePreference>(
            segments: [
              ButtonSegment(
                value: AppThemePreference.system,
                label: Text(l10n.settingsSystem),
                icon: const Icon(Icons.brightness_auto, size: 18),
              ),
              ButtonSegment(
                value: AppThemePreference.light,
                label: Text(l10n.settingsThemeLight),
                icon: const Icon(Icons.light_mode_outlined, size: 18),
              ),
              ButtonSegment(
                value: AppThemePreference.dark,
                label: Text(l10n.settingsThemeDark),
                icon: const Icon(Icons.dark_mode_outlined, size: 18),
              ),
            ],
            selected: {settings.theme},
            onSelectionChanged: (selected) {
              controller.setTheme(selected.first);
            },
          ),
        ],
      ),
    );
  }
}
