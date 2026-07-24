/// Read-only group-level inventory totals card (#508).
///
/// Rendered as the last item in each merchandise group list/grid. Shows the
/// sum of HAVE / WANT / TRADE quantities for items currently visible in that
/// group, respecting [InventoryDisplayMode] (same flags as item tiles).
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'merch_filters.dart';

/// Key used in widget tests to find the group totals card.
const Key groupInventoryTotalsCardKey = Key('groupInventoryTotalsCard');

/// Distinct summary card: no photo, no steppers — only aggregated counts.
class GroupInventoryTotalsCard extends StatelessWidget {
  const GroupInventoryTotalsCard({
    super.key,
    required this.totals,
    required this.displayMode,
    this.compact = false,
  });

  final GroupInventoryTotals totals;
  final InventoryDisplayMode displayMode;

  /// Tighter layout for grid cells (tall aspect ratio).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final flags = inventoryDisplayFlags(displayMode);
    final theme = Theme.of(context);

    final counters = <Widget>[
      if (flags.showHave)
        _TotalCounter(
          label: l10n.haveShort,
          fullLabel: l10n.have,
          qty: totals.totalHave,
          color: AppTheme.haveColor,
          compact: compact,
        ),
      if (flags.showWant)
        _TotalCounter(
          label: l10n.wantShort,
          fullLabel: l10n.want,
          qty: totals.totalWant,
          color: AppTheme.wantColor,
          compact: compact,
        ),
      if (flags.showTrade)
        _TotalCounter(
          label: l10n.tradeShort,
          fullLabel: l10n.trade,
          qty: totals.totalTrade,
          color: AppTheme.tradeColor,
          compact: compact,
        ),
    ];

    final body = compact
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                l10n.groupInventoryTotal,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ...counters.map(
                (c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: c,
                ),
              ),
            ],
          )
        : Row(
            children: [
              Icon(Icons.functions, size: 20, color: Colors.blueGrey.shade600),
              const SizedBox(width: 8),
              Text(
                l10n.groupInventoryTotal,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              ...counters.expand((c) => [const SizedBox(width: 8), c]),
            ],
          );

    return Card(
      key: groupInventoryTotalsCardKey,
      margin: compact
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.blueGrey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.blueGrey.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 8 : 12,
        ),
        child: body,
      ),
    );
  }
}

class _TotalCounter extends StatelessWidget {
  const _TotalCounter({
    required this.label,
    required this.fullLabel,
    required this.qty,
    required this.color,
    required this.compact,
  });

  final String label;
  final String fullLabel;
  final int qty;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bg = qty > 0 ? color.withValues(alpha: 0.12) : Colors.transparent;
    return Semantics(
      label: '$fullLabel: $qty',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: compact ? 10 : 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            SizedBox(width: compact ? 4 : 6),
            Text(
              '$qty',
              style: TextStyle(
                fontSize: compact ? 12 : 14,
                fontWeight: FontWeight.bold,
                color: qty > 0 ? color : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
