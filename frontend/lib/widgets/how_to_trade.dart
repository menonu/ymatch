import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';

/// Renders the "How to Trade" guide — a title row plus three numbered steps.
///
/// This is the single source of truth for the guide content, so the Profile
/// card and the Home AppBar info-icon sheet show the exact same steps (sourced
/// from the `howToTrade` / `tradeStep1–3` l10n keys). Extracted in #336 so new
/// users can reach the guide without digging into the Profile tab.
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
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

/// Opens the how-to guide as a modal bottom sheet. Used by the Home AppBar
/// info icon so a logged-in user can read the guide without navigating to the
/// Profile tab.
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

/// The AppBar help icon that opens the how-to guide sheet (#336).
///
/// Reused by the Home and Event Detail screens so the entry point is
/// consistent. On a user's first login (before they have opened the guide) the
/// icon is emphasized — rendered in the primary color with a small badge dot —
/// to draw attention to it; once opened it becomes a plain icon (the
/// "seen" state persists across sessions via [howToHintSeenProvider]).
class HowToTradeIconButton extends ConsumerWidget {
  const HowToTradeIconButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final seen = ref.watch(howToHintSeenProvider);
    final primary = Theme.of(context).colorScheme.primary;

    Future<void> onTap() async {
      if (!seen) await ref.read(howToHintSeenProvider.notifier).markSeen();
      if (!context.mounted) return;
      await showHowToTradeSheet(context);
    }

    final icon = Icon(Icons.help_outline, color: seen ? null : primary);
    return IconButton(
      icon: seen
          ? icon
          // Emphasize on first login: primary-colored icon + attention dot.
          : Badge(backgroundColor: primary, child: icon),
      tooltip: l10n.howToTrade,
      onPressed: onTap,
    );
  }
}

/// A long downward arrow drawn on the login screen to draw the user's eye from
/// the hint text down to the virtual Profile tab in the bottom-nav area (#336).
class LongDownArrow extends StatelessWidget {
  final double height;
  final Color color;

  const LongDownArrow({super.key, this.height = 72, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: height,
      child: CustomPaint(painter: _DownArrowPainter(color: color)),
    );
  }
}

class _DownArrowPainter extends CustomPainter {
  final Color color;

  const _DownArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final cx = size.width / 2;
    // Shaft.
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height - 10), paint);
    // Arrowhead.
    final tip = Offset(cx, size.height);
    canvas.drawLine(Offset(cx - 6, size.height - 14), tip, paint);
    canvas.drawLine(Offset(cx + 6, size.height - 14), tip, paint);
  }

  @override
  bool shouldRepaint(_DownArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Draws a dashed (dotted) rounded-rectangle outline over its child — used to
/// mark the virtual bottom-nav preview as a "preview" rather than the real
/// control, without taking any layout space (foreground painter).
class DashedOutline extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;
  final double strokeWidth;

  const DashedOutline({
    super.key,
    required this.child,
    required this.color,
    this.radius = 12,
    this.strokeWidth = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(
        color: color,
        radius: radius,
        strokeWidth: strokeWidth,
      ),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;

  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    canvas.drawPath(_dashPath(path), paint);
  }

  Path _dashPath(Path source, {double dash = 5, double gap = 4}) {
    final dest = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final len = distance + dash < metric.length
            ? dash
            : metric.length - distance;
        dest.addPath(metric.extractPath(distance, distance + len), Offset.zero);
        distance += dash + gap;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// A "virtual" preview of the bottom-nav Profile tab, shown on the login
/// screen in the same area the real navigation bar occupies after login.
///
/// Only the Profile tab is rendered — the Items and Matches tabs are
/// irrelevant to this pointer and are hidden, but the Profile tab keeps its
/// real position (the rightmost of three equal-width slots, so its center sits
/// where it will after login). A long arrow is drawn directly above it,
/// pointing straight down at it. The tab is ghosted (dashed outline) and
/// disabled — tapping it does NOT open the guide; it only tells the user the
/// tab is available after login (#336).
class VirtualProfileTabBar extends StatelessWidget {
  const VirtualProfileTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final primary = Theme.of(context).colorScheme.primary;

    return SafeArea(
      top: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Items slot — hidden (kept as empty space so the Profile tab stays
          // in its real rightmost-of-three position).
          const Expanded(child: SizedBox.shrink()),
          // Matches slot — hidden, same reason.
          const Expanded(child: SizedBox.shrink()),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LongDownArrow(color: primary, height: 56),
                _ProfileTab(
                  label: l10n.navProfile,
                  color: primary,
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.howToPreviewTabHint)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The single virtual Profile "tab" — a person icon in a selected-style pill
/// with the label beneath, wrapped in a dashed outline to read as a preview.
class _ProfileTab extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ProfileTab({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: DashedOutline(
        color: color.withValues(alpha: 0.6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.person, color: color, size: 24),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
