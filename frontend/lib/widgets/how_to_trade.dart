import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Renders the "How to Trade" guide — a title row plus three numbered steps.
///
/// This is the single source of truth for the guide content, so the Profile
/// card, the login-screen preview, and the Home AppBar info icon all show the
/// exact same steps (sourced from the `howToTrade` / `tradeStep1–3` l10n keys).
/// Extracted in #336 so new users can reach the guide without digging into the
/// Profile tab.
class HowToTradeContent extends StatelessWidget {
  const HowToTradeContent({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.help_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              l10n.howToTrade,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 16),
        HowToTradeStep(step: '1', text: l10n.tradeStep1),
        HowToTradeStep(step: '2', text: l10n.tradeStep2),
        HowToTradeStep(step: '3', text: l10n.tradeStep3),
      ],
    );
  }
}

/// A single numbered instruction row in the how-to guide.
class HowToTradeStep extends StatelessWidget {
  final String step;
  final String text;

  const HowToTradeStep({super.key, required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              step,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Opens the how-to guide as a modal bottom sheet. Used by the login-screen
/// preview and the Home AppBar info icon so a user can read the guide without
/// navigating to the Profile tab.
Future<void> showHowToTradeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: HowToTradeContent(),
      ),
    ),
  );
}

/// A login-screen pointer that tells brand-new users the how-to guide lives
/// behind the Profile tab. It renders a hint text, a downward arrow, and a
/// dashed "virtual" Profile tab preview (mimicking the real bottom-nav
/// Profile destination — `Icons.person_outline` / `navProfile`). Tapping the
/// preview opens the guide sheet so the user can read it before logging in.
///
/// The dashed outline conveys that this is a preview of the tab, not the tab
/// itself (the real bottom-nav Profile tab only appears post-login).
class HowToTradePreview extends StatelessWidget {
  final VoidCallback onTap;

  const HowToTradePreview({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.howToHint,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        const SizedBox(height: 10),
        Icon(Icons.arrow_downward_rounded, size: 20, color: primary),
        const SizedBox(height: 4),
        InkWell(
          key: const ValueKey('howToPreviewButton'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: _DashedBorder(
            color: primary,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outline, size: 20, color: primary),
                const SizedBox(width: 6),
                Text(
                  l10n.navProfile,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Draws a dashed (dotted) rounded rectangle outline around its child — used
/// to visually distinguish the virtual "Profile" tab preview from a real
/// button on the login screen.
class _DashedBorder extends StatelessWidget {
  final Widget child;
  final Color color;

  const _DashedBorder({required this.child, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(color: color),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;

  const _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );
    final path = Path()..addRRect(rrect);
    canvas.drawPath(dashPath(path), paint);
  }

  Path dashPath(Path source, {double dash = 5, double gap = 4}) {
    final dest = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final len = distance + dash < metric.length ? dash : metric.length - distance;
        dest.addPath(metric.extractPath(distance, distance + len), Offset.zero);
        distance += dash + gap;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}