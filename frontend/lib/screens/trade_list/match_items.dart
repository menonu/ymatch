import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_helper.dart';

/// Potential HAVE/WANT chips before a concrete offer is selected.
class MatchPotentialItems extends StatelessWidget {
  const MatchPotentialItems({super.key, required this.match, this.groupLabel});

  final TradeMatch match;

  /// Cosmetic group label shown once on the left of each give/receive row
  /// (#534). Same value on both sides by ADR 0001; null when the match has
  /// no group name.
  final String? groupLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (match.userHaves.isNotEmpty) ...[
          Text(
            l10n.youGive,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          MatchExchangeRow(
            groupLabel: groupLabel,
            child: MatchItemChips(
              items: match.userHaves,
              color: AppTheme.tradeColor,
            ),
          ),
        ],
        if (match.userWants.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            l10n.youReceive,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          MatchExchangeRow(
            groupLabel: groupLabel,
            child: MatchItemChips(
              items: match.userWants,
              color: AppTheme.wantColor,
            ),
          ),
        ],
      ],
    );
  }
}

class MatchItemChips extends StatelessWidget {
  const MatchItemChips({super.key, required this.items, required this.color});

  final List<InventoryItem> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: items.map((item) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(
            '${item.merchName} ×${item.quantity}',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Selected proposal legs split into give / receive for the viewer.
class MatchSelectedItems extends StatelessWidget {
  const MatchSelectedItems({
    super.key,
    required this.userId,
    required this.match,
    this.groupLabel,
  });

  final int userId;
  final TradeMatch match;

  /// Cosmetic group label shown once on the left of each give/receive row
  /// (#534). Same value on both sides by ADR 0001; null when the match has
  /// no group name.
  final String? groupLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final gives = match.selectedItems
        .where((i) => i.giverUserId == userId)
        .toList();
    final receives = match.selectedItems
        .where((i) => i.giverUserId != userId)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (gives.isNotEmpty) ...[
          Text(
            l10n.giveLabel,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          MatchExchangeRow(
            groupLabel: groupLabel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final i in gives)
                  MatchItemRow(item: i, color: AppTheme.tradeColor),
              ],
            ),
          ),
        ],
        if (receives.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            l10n.receiveLabel,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          MatchExchangeRow(
            groupLabel: groupLabel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final i in receives)
                  MatchItemRow(item: i, color: AppTheme.wantColor),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Layout helper: optional group name on the left of an exchange-items body
/// (#534). Used once per give section and once per receive section.
class MatchExchangeRow extends StatelessWidget {
  const MatchExchangeRow({super.key, required this.child, this.groupLabel});

  final Widget child;
  final String? groupLabel;

  @override
  Widget build(BuildContext context) {
    final label = groupLabel;
    if (label == null || label.isEmpty) return child;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class MatchItemRow extends StatelessWidget {
  const MatchItemRow({super.key, required this.item, required this.color});

  final MatchItem item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 28,
              height: 28,
              child: buildImage(
                item.hasPhotoUrl() ? item.photoUrl : null,
                width: 28,
                height: 28,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${item.merchName} ×${item.quantity}',
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
