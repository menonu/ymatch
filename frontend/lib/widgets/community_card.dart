import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';

/// Official community links on the Settings tab (#570).
///
/// Icons only — brand names live in tooltips / semantics, not as labels.
/// Marks are the Simple Icons SVGs in `frontend/icons/`.
class CommunityCard extends StatelessWidget {
  const CommunityCard({super.key, this.launchUrlOverride});

  /// Test seam; production uses [launchUrl] in an external application.
  final Future<bool> Function(Uri uri)? launchUrlOverride;

  static final xUri = Uri.parse('https://x.com/ymatchdev');
  static final discordUri = Uri.parse('https://discord.gg/QWcCJspb7T');

  static const xIconAsset = 'icons/x.svg';
  static const discordIconAsset = 'icons/discord.svg';

  static final ButtonStyle _iconHitTarget = IconButton.styleFrom(
    minimumSize: const Size(48, 48),
    tapTargetSize: MaterialTapTargetSize.padded,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final iconColor = Theme.of(context).colorScheme.onSurface;

    return Card(
      key: const Key('community-section'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.community,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('community-x'),
                  tooltip: l10n.communityXTooltip,
                  style: _iconHitTarget,
                  onPressed: () => _open(context, xUri, l10n),
                  icon: _BrandIcon(asset: xIconAsset, color: iconColor),
                ),
                IconButton(
                  key: const Key('community-discord'),
                  tooltip: l10n.communityDiscordTooltip,
                  style: _iconHitTarget,
                  onPressed: () => _open(context, discordUri, l10n),
                  icon: _BrandIcon(asset: discordIconAsset, color: iconColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    Uri uri,
    AppLocalizations l10n,
  ) async {
    try {
      final open =
          launchUrlOverride ??
          ((u) => launchUrl(u, mode: LaunchMode.externalApplication));
      final ok = await open(uri);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorPrefix('Could not open link'))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.errorPrefix(e.toString()))));
      }
    }
  }
}

class _BrandIcon extends StatelessWidget {
  const _BrandIcon({required this.asset, required this.color});

  final String asset;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: 22,
      height: 22,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }
}
