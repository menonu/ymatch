import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';

/// Official community links on the Settings tab (#570).
///
/// Icons only — brand names live in tooltips / semantics, not as labels.
class CommunityCard extends StatelessWidget {
  const CommunityCard({super.key, this.launchUrlOverride});

  /// Test seam; production uses [launchUrl] in an external application.
  final Future<bool> Function(Uri uri)? launchUrlOverride;

  static final xUri = Uri.parse('https://x.com/ymatchdev');
  static final discordUri = Uri.parse('https://discord.gg/QWcCJspb7T');

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
                  icon: _BrandXIcon(color: iconColor),
                ),
                IconButton(
                  key: const Key('community-discord'),
                  tooltip: l10n.communityDiscordTooltip,
                  style: _iconHitTarget,
                  onPressed: () => _open(context, discordUri, l10n),
                  icon: const _BrandDiscordIcon(),
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

/// Official X logo (24×24 viewBox, even-odd cutout).
class _BrandXIcon extends StatelessWidget {
  const _BrandXIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _XLogoPainter(color)),
    );
  }
}

class _XLogoPainter extends CustomPainter {
  const _XLogoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(18.901, 1.153)
      ..lineTo(22.581, 1.153)
      ..lineTo(14.541, 10.343)
      ..lineTo(24, 22.846)
      ..lineTo(16.594, 22.846)
      ..lineTo(10.794, 15.262)
      ..lineTo(4.156, 22.846)
      ..lineTo(0.474, 22.846)
      ..lineTo(9.074, 13.016)
      ..lineTo(0, 1.154)
      ..lineTo(7.594, 1.154)
      ..lineTo(12.837, 8.086)
      ..close()
      ..moveTo(17.61, 20.644)
      ..lineTo(19.649, 20.644)
      ..lineTo(6.486, 3.24)
      ..lineTo(4.298, 3.24)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _XLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Discord mark (blurple body, cut-out eyes).
class _BrandDiscordIcon extends StatelessWidget {
  const _BrandDiscordIcon();

  static const _blurple = Color(0xFF5865F2);

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 24,
      height: 24,
      child: CustomPaint(painter: _DiscordLogoPainter(_blurple)),
    );
  }
}

class _DiscordLogoPainter extends CustomPainter {
  const _DiscordLogoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final body = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(4.2, 8.2)
      ..cubicTo(4.4, 5.2, 7.1, 3.4, 10.4, 3.2)
      ..lineTo(13.6, 3.2)
      ..cubicTo(16.9, 3.4, 19.6, 5.2, 19.8, 8.2)
      ..cubicTo(20.4, 13.4, 19.7, 17.8, 18.9, 19.4)
      ..cubicTo(18.2, 20.7, 16.5, 21.4, 15.1, 21.8)
      ..lineTo(13.9, 19.7)
      ..cubicTo(14.7, 19.4, 15.5, 19.0, 16.2, 18.5)
      ..cubicTo(13.4, 19.8, 10.6, 19.8, 7.8, 18.5)
      ..cubicTo(8.5, 19.0, 9.3, 19.4, 10.1, 19.7)
      ..lineTo(8.9, 21.8)
      ..cubicTo(7.5, 21.4, 5.8, 20.7, 5.1, 19.4)
      ..cubicTo(4.3, 17.8, 3.6, 13.4, 4.2, 8.2)
      ..close()
      ..addOval(Rect.fromCircle(center: const Offset(9.0, 12.6), radius: 1.55))
      ..addOval(
        Rect.fromCircle(center: const Offset(15.0, 12.6), radius: 1.55),
      );
    canvas.drawPath(body, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _DiscordLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}
