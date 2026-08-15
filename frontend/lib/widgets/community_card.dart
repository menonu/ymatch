import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';

/// Official community links on the Settings tab (#570, #572, #573).
///
/// Icons only — brand names live in tooltips / semantics, not as labels.
/// Marks are the Simple Icons SVGs in `frontend/icons/`.
///
/// X and Discord destinations come from `--dart-define` (`X_PROFILE_URL`,
/// `DISCORD_INVITE_URL`), injected at deploy from GitHub Secrets. Those icons
/// are omitted when the URL is unset or not `https`. GitHub is always shown
/// with a hardcoded public repo URL (#573).
class CommunityCard extends StatelessWidget {
  const CommunityCard({
    super.key,
    this.launchUrlOverride,
    this.xProfileUrl,
    this.discordInviteUrl,
  });

  /// Test seam; production uses [launchUrl] in an external application.
  final Future<bool> Function(Uri uri)? launchUrlOverride;

  /// Test / explicit override. Production reads [xProfileUrlFromEnvironment].
  final String? xProfileUrl;

  /// Test / explicit override. Production reads [discordInviteUrlFromEnvironment].
  final String? discordInviteUrl;

  static const xProfileUrlFromEnvironment = String.fromEnvironment(
    'X_PROFILE_URL',
  );
  static const discordInviteUrlFromEnvironment = String.fromEnvironment(
    'DISCORD_INVITE_URL',
  );

  /// Public source repository — hardcoded, not secret-injected (#573).
  static const githubRepoUrl = 'https://github.com/menonu/ymatch';

  static const xIconAsset = 'icons/x.svg';
  static const discordIconAsset = 'icons/discord.svg';
  static const githubIconAsset = 'icons/github.svg';

  /// Accepts trimmed `https` URLs only; anything else is treated as unset.
  static Uri? resolveHttpsUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  static final ButtonStyle _iconHitTarget = IconButton.styleFrom(
    minimumSize: const Size(48, 48),
    tapTargetSize: MaterialTapTargetSize.padded,
  );

  Uri? get _xUri => resolveHttpsUrl(xProfileUrl ?? xProfileUrlFromEnvironment);

  Uri? get _discordUri =>
      resolveHttpsUrl(discordInviteUrl ?? discordInviteUrlFromEnvironment);

  Uri get _githubUri => Uri.parse(githubRepoUrl);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final iconColor = Theme.of(context).colorScheme.onSurface;
    final xUri = _xUri;
    final discordUri = _discordUri;
    final githubUri = _githubUri;

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
                if (xUri != null)
                  IconButton(
                    key: const Key('community-x'),
                    tooltip: l10n.communityXTooltip,
                    style: _iconHitTarget,
                    onPressed: () => _open(context, xUri, l10n),
                    icon: _BrandIcon(asset: xIconAsset, color: iconColor),
                  ),
                if (discordUri != null)
                  IconButton(
                    key: const Key('community-discord'),
                    tooltip: l10n.communityDiscordTooltip,
                    style: _iconHitTarget,
                    onPressed: () => _open(context, discordUri, l10n),
                    icon: _BrandIcon(asset: discordIconAsset, color: iconColor),
                  ),
                IconButton(
                  key: const Key('community-github'),
                  tooltip: l10n.communityGitHubTooltip,
                  style: _iconHitTarget,
                  onPressed: () => _open(context, githubUri, l10n),
                  icon: _BrandIcon(asset: githubIconAsset, color: iconColor),
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
