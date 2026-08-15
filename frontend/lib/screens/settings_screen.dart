import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';

/// Language + match-notification prefs, inlined on the Settings tab (#562).
///
/// Theme control removed temporarily (#553) due to dark-mode visibility issues.
/// Match notifications (Web Push) live here (#179).
class AppSettingsSection extends ConsumerWidget {
  const AppSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final push = ref.watch(webPushProvider);
    final pushCtrl = ref.read(webPushProvider.notifier);

    return Card(
      key: const Key('app-settings-section'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.settings,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.settingsLanguage,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SegmentedButton<AppLanguagePreference>(
              showSelectedIcon: false,
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
            const SizedBox(height: 28),
            Text(
              l10n.settingsNotifications,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.settingsNotificationsSubtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _NotificationsTile(
              push: push,
              l10n: l10n,
              onChanged: push.canToggle
                  ? (value) => pushCtrl.setEnabled(value)
                  : null,
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 8),
              Text(
                l10n.settingsNotificationsIosHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotificationsTile extends StatelessWidget {
  const _NotificationsTile({
    required this.push,
    required this.l10n,
    required this.onChanged,
  });

  final WebPushState push;
  final AppLocalizations l10n;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = switch (push.status) {
      WebPushUiStatus.loading => null,
      WebPushUiStatus.unsupported => l10n.settingsNotificationsUnsupported,
      WebPushUiStatus.serverDisabled => l10n.settingsNotificationsServerOff,
      WebPushUiStatus.denied => l10n.settingsNotificationsDenied,
      WebPushUiStatus.error => push.message ?? l10n.settingsNotificationsError,
      WebPushUiStatus.off || WebPushUiStatus.on => null,
    };

    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: push.status == WebPushUiStatus.loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              push.isOn
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
            ),
      // Section header already says "Match notifications"; tile shows subtitle.
      title: Text(l10n.settingsNotificationsSubtitle),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    push.status == WebPushUiStatus.error ||
                        push.status == WebPushUiStatus.denied
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      value: push.isOn,
      onChanged: onChanged,
    );
  }
}
