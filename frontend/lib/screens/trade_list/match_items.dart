import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_helper.dart';

/// Potential HAVE/WANT lines before a concrete offer is selected.
class MatchPotentialItems extends StatelessWidget {
  const MatchPotentialItems({super.key, required this.match, this.groupLabel});

  final TradeMatch match;

  /// Cosmetic group label shown to the right of each give/receive section
  /// title (#534 / #542). Same value on both sides by ADR 0001; null when the
  /// match has no group name.
  final String? groupLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (match.userHaves.isNotEmpty) ...[
          MatchSectionTitle(title: l10n.youGive, groupLabel: groupLabel),
          const SizedBox(height: 4),
          MatchInventoryItemList(
            items: match.userHaves,
            color: AppTheme.tradeColor,
          ),
        ],
        if (match.userWants.isNotEmpty) ...[
          const SizedBox(height: 6),
          MatchSectionTitle(title: l10n.youReceive, groupLabel: groupLabel),
          const SizedBox(height: 4),
          MatchInventoryItemList(
            items: match.userWants,
            color: AppTheme.wantColor,
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

  /// Cosmetic group label shown to the right of each give/receive section
  /// title (#534 / #542). Same value on both sides by ADR 0001; null when the
  /// match has no group name.
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
          MatchSectionTitle(title: l10n.giveLabel, groupLabel: groupLabel),
          const SizedBox(height: 4),
          Column(
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
        ],
        if (receives.isNotEmpty) ...[
          const SizedBox(height: 6),
          MatchSectionTitle(title: l10n.receiveLabel, groupLabel: groupLabel),
          const SizedBox(height: 4),
          Column(
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
        ],
      ],
    );
  }
}

/// Section header: "You give:" / "あなたが渡すもの:" with optional group chip
/// immediately to the right (#534 layout update).
class MatchSectionTitle extends StatelessWidget {
  const MatchSectionTitle({super.key, required this.title, this.groupLabel});

  final String title;
  final String? groupLabel;

  @override
  Widget build(BuildContext context) {
    final label = groupLabel;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (label != null && label.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(child: MatchGroupChip(label: label)),
        ],
      ],
    );
  }
}

/// Rounded bordered pill for the match group name next to section titles.
class MatchGroupChip extends StatelessWidget {
  const MatchGroupChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('match_group_chip_$label'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade400),
        color: Colors.grey.shade50,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey[800],
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Thumbnail edge length for match item rows. Match-card only.
const double kMatchMerchThumbnailSize = 48;

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
    const size = kMatchMerchThumbnailSize;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // #540 / #542: thumbnail; tap to zoom when a photo exists.
          ZoomableImage(
            key: Key('match_merch_thumbnail_$merchId'),
            photoUrl: url,
            semanticLabel: l10n.viewFullImage,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: size,
                height: size,
                child: buildImage(
                  url,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
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
