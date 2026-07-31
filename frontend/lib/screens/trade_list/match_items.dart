import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_helper.dart';

/// Potential HAVE/WANT lines before a concrete offer is selected.
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
            child: MatchInventoryItemList(
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
            child: MatchInventoryItemList(
              items: match.userWants,
              color: AppTheme.wantColor,
            ),
          ),
        ],
      ],
    );
  }
}

/// Potential inventory candidates: one merch row per line with thumbnail (#542).
class MatchInventoryItemList extends StatelessWidget {
  const MatchInventoryItemList({
    super.key,
    required this.items,
    required this.color,
  });

  final List<InventoryItem> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          MatchMerchLine(
            merchId: item.merchId,
            merchName: item.merchName,
            quantity: item.quantity,
            color: color,
            photoUrl: item.hasPhotoUrl() ? item.photoUrl : null,
          ),
      ],
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
                  MatchMerchLine(
                    merchId: i.merchId,
                    merchName: i.merchName,
                    quantity: i.quantity,
                    color: AppTheme.tradeColor,
                    photoUrl: i.hasPhotoUrl() ? i.photoUrl : null,
                  ),
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
                  MatchMerchLine(
                    merchId: i.merchId,
                    merchName: i.merchName,
                    quantity: i.quantity,
                    color: AppTheme.wantColor,
                    photoUrl: i.hasPhotoUrl() ? i.photoUrl : null,
                  ),
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

/// One merch line on a match card: thumbnail + "Name ×qty" (#542).
///
/// Shared by potential inventory candidates and selected offer legs so both
/// render as a vertical list (one item per row) with the same chrome.
class MatchMerchLine extends StatelessWidget {
  const MatchMerchLine({
    super.key,
    required this.merchId,
    required this.merchName,
    required this.quantity,
    required this.color,
    this.photoUrl,
  });

  final int merchId;
  final String merchName;
  final int quantity;
  final Color color;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final url = photoUrl;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          // #540 / #542: compact 28×28 thumb; tap to zoom when a photo exists.
          ZoomableImage(
            key: Key('match_merch_thumbnail_$merchId'),
            photoUrl: url,
            semanticLabel: l10n.viewFullImage,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 28,
                height: 28,
                child: buildImage(
                  url,
                  width: 28,
                  height: 28,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$merchName ×$quantity',
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
