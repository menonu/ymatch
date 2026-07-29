import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import 'match_balance.dart';

/// Opens the make/counter-offer dialog for [match].
///
/// On confirm, [onSubmit] receives the accumulating partial-update leg list
/// (qty 0 removes a prefilled leg). Caller owns MatchController submission.
Future<void> showTradeOfferDialog({
  required BuildContext context,
  required User user,
  required TradeMatch match,
  required void Function(List<OfferItem> items) onSubmit,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) =>
        TradeOfferDialog(user: user, match: match, onSubmit: onSubmit),
  );
}

/// Stateful offer panel: both give/receive sections always visible (#303),
/// qty steppers capped to listing LEAST (#294/#297).
class TradeOfferDialog extends StatefulWidget {
  const TradeOfferDialog({
    super.key,
    required this.user,
    required this.match,
    required this.onSubmit,
  });

  final User user;
  final TradeMatch match;
  final void Function(List<OfferItem> items) onSubmit;

  @override
  State<TradeOfferDialog> createState() => _TradeOfferDialogState();
}

class _TradeOfferDialogState extends State<TradeOfferDialog> {
  late final int _meId;
  late final int _otherId;
  late final List<InventoryItem> _giveItems;
  late final List<InventoryItem> _receiveItems;

  final _giveOn = <int, bool>{};
  final _giveQty = <int, int>{};
  final _giveInitially = <int>{};
  final _receiveOn = <int, bool>{};
  final _receiveQty = <int, int>{};
  final _receiveInitially = <int>{};

  @override
  void initState() {
    super.initState();
    final match = widget.match;
    _meId = widget.user.id;
    _otherId = _meId == match.user1Id ? match.user2Id : match.user1Id;

    // Candidates: give = my TRADE items (cap = receiver's want, already
    // capped by the listing query LEAST); receive = other's TRADE items I
    // want (cap = my want).
    _giveItems = match.userHaves;
    _receiveItems = match.userWants;

    // Selection state, pre-filled from existing legs (counter-offer).
    for (final leg in match.selectedItems) {
      if (leg.giverUserId == _meId) {
        _giveOn[leg.merchId] = true;
        _giveQty[leg.merchId] = leg.quantity;
        _giveInitially.add(leg.merchId);
      } else {
        _receiveOn[leg.merchId] = true;
        _receiveQty[leg.merchId] = leg.quantity;
        _receiveInitially.add(leg.merchId);
      }
    }
    for (final i in _giveItems) {
      _giveOn.putIfAbsent(i.merchId, () => false);
      _giveQty.putIfAbsent(i.merchId, () => 1);
    }
    for (final i in _receiveItems) {
      _receiveOn.putIfAbsent(i.merchId, () => false);
      _receiveQty.putIfAbsent(i.merchId, () => 1);
    }
  }

  /// Projected per-side totals after applying the dialog edits to the
  /// existing legs. Both sections are always shown (#303); the accumulating
  /// partial-update still holds because only checked legs are submitted.
  (int, int) _projectedTotals() {
    final give = <int, int>{};
    final recv = <int, int>{};
    for (final leg in widget.match.selectedItems) {
      if (leg.giverUserId == _meId) {
        give[leg.merchId] = leg.quantity;
      } else {
        recv[leg.merchId] = leg.quantity;
      }
    }
    for (final i in _giveItems) {
      if (_giveOn[i.merchId] == true) {
        give[i.merchId] = _giveQty[i.merchId] ?? 1;
      } else if (_giveInitially.contains(i.merchId)) {
        give[i.merchId] = 0;
      }
    }
    for (final i in _receiveItems) {
      if (_receiveOn[i.merchId] == true) {
        recv[i.merchId] = _receiveQty[i.merchId] ?? 1;
      } else if (_receiveInitially.contains(i.merchId)) {
        recv[i.merchId] = 0;
      }
    }
    final g = give.values.fold(0, (a, b) => a + b);
    final r = recv.values.fold(0, (a, b) => a + b);
    return (g, r);
  }

  List<OfferItem> _buildItems() {
    final items = <OfferItem>[];
    for (final i in _giveItems) {
      if (_giveOn[i.merchId] == true) {
        items.add(
          OfferItem()
            ..merchId = i.merchId
            ..giverUserId = _meId
            ..quantity = _giveQty[i.merchId] ?? 1,
        );
      } else if (_giveInitially.contains(i.merchId)) {
        // Uncheck a prefilled leg → remove it (qty 0, accumulating).
        items.add(
          OfferItem()
            ..merchId = i.merchId
            ..giverUserId = _meId
            ..quantity = 0,
        );
      }
    }
    for (final i in _receiveItems) {
      if (_receiveOn[i.merchId] == true) {
        items.add(
          OfferItem()
            ..merchId = i.merchId
            ..giverUserId = _otherId
            ..quantity = _receiveQty[i.merchId] ?? 1,
        );
      } else if (_receiveInitially.contains(i.merchId)) {
        items.add(
          OfferItem()
            ..merchId = i.merchId
            ..giverUserId = _otherId
            ..quantity = 0,
        );
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = _buildItems();
    final hasChange = items.isNotEmpty;
    final (g, r) = _projectedTotals();
    final legCount = items.where((i) => i.quantity > 0).length;

    return AlertDialog(
      title: Text(l10n.makeTradeOffer),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MatchBalanceIndicator(give: g, receive: r),
            const SizedBox(height: 4),
            Text(
              l10n.balanceExplanation,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            if (_giveItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n.itemsYouGive,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 4),
              ..._giveItems.map(
                (item) => _OfferLegRow(
                  item: item,
                  selected: _giveOn[item.merchId] ?? false,
                  qty: _giveQty[item.merchId] ?? 1,
                  onToggle: (v) =>
                      setState(() => _giveOn[item.merchId] = v ?? false),
                  onQty: (q) => setState(() => _giveQty[item.merchId] = q),
                ),
              ),
            ],
            if (_receiveItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n.itemsYouReceive,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 4),
              ..._receiveItems.map(
                (item) => _OfferLegRow(
                  item: item,
                  selected: _receiveOn[item.merchId] ?? false,
                  qty: _receiveQty[item.merchId] ?? 1,
                  onToggle: (v) =>
                      setState(() => _receiveOn[item.merchId] = v ?? false),
                  onQty: (q) => setState(() => _receiveQty[item.merchId] = q),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: hasChange
              ? () {
                  Navigator.pop(context);
                  widget.onSubmit(items);
                }
              : null,
          child: Text(l10n.sendOfferItems(legCount)),
        ),
      ],
    );
  }
}

class _OfferLegRow extends StatelessWidget {
  const _OfferLegRow({
    required this.item,
    required this.selected,
    required this.qty,
    required this.onToggle,
    required this.onQty,
  });

  final InventoryItem item;
  final bool selected;
  final int qty;
  final ValueChanged<bool?> onToggle;
  final ValueChanged<int> onQty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            // Stepper 1..cap so the user cannot over-offer (#294/#297). cap =
            // item.quantity (already LEAST(trade, want) from the listing).
            onChanged: onToggle,
            activeColor: AppTheme.tradeColor,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.merchName, style: const TextStyle(fontSize: 14)),
                Text(
                  l10n.qtyLabel(item.quantity),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          // Offer-dialog qty controls unchanged from main (#538 = detailed only).
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: selected && qty > 1 ? () => onQty(qty - 1) : null,
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$qty',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: selected && qty < item.quantity
                ? () => onQty(qty + 1)
                : null,
          ),
        ],
      ),
    );
  }
}
