import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/format_local_datetime.dart';
import 'trade_list/match_card.dart';
import 'trade_list/trade_tab.dart';

export 'trade_list/trade_tab.dart';

class TradeListScreen extends ConsumerStatefulWidget {
  const TradeListScreen({super.key});

  @override
  ConsumerState<TradeListScreen> createState() => _TradeListScreenState();
}

class _TradeListScreenState extends ConsumerState<TradeListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<TradeMatch> _filterMatches(
    List<TradeMatch> matches,
    TradeTab tab,
    int userId,
  ) {
    // ADR 0010: CANCELLED is system-only (not user-actionable) but surfaces
    // under Done alongside COMPLETED. Actionable tabs exclude it.
    final Iterable<TradeMatch> filtered;
    switch (tab) {
      case TradeTab.match_:
        filtered = matches.where((m) => m.status == 'PENDING');
      case TradeTab.offerOut:
        filtered = matches.where(
          (m) => m.status == 'OFFERED' && m.offeredBy == userId,
        );
      case TradeTab.offerIn:
        filtered = matches.where(
          (m) => m.status == 'OFFERED' && m.offeredBy != userId,
        );
      case TradeTab.active:
        filtered = matches.where((m) => m.status == 'ACCEPTED');
      case TradeTab.completed:
        filtered = matches.where(
          (m) => m.status == 'COMPLETED' || m.status == 'CANCELLED',
        );
    }
    // #476: latest-first by created_at (defensive — do not rely on server
    // order alone after client-side tab filtering).
    final list = filtered.toList();
    list.sort(
      (a, b) => compareIsoDateTimeDesc(
        a.hasCreatedAt() ? a.createdAt : null,
        b.hasCreatedAt() ? b.createdAt : null,
        fallback: () => b.id.compareTo(a.id),
      ),
    );
    return list;
  }

  int _tabCount(List<TradeMatch> matches, TradeTab tab, int userId) {
    return _filterMatches(matches, tab, userId).length;
  }

  // #241: thin wrappers — body shape, invalidation, and error state live
  // on MatchController. Errors surface via ref.listen in build().
  Future<void> _updateStatus(int userId, int matchId, String newStatus) {
    return ref
        .read(matchControllerProvider.notifier)
        .updateStatus(userId, matchId, newStatus);
  }

  Future<void> _submitOffer(int userId, int matchId, List<OfferItem> items) {
    return ref
        .read(matchControllerProvider.notifier)
        .submitOffer(userId, matchId, items);
  }

  Future<void> _applyInventory(int userId, int matchId) async {
    final l10n = AppLocalizations.of(context)!;
    var skipHaveDecrement = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(l10n.updateInventory),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.applyInventoryConfirmBody),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: skipHaveDecrement,
                    onChanged: (v) =>
                        setLocal(() => skipHaveDecrement = v ?? false),
                    title: Text(l10n.skipHaveDecrementLabel),
                    subtitle: Text(l10n.skipHaveDecrementHint),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.updateInventory),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || !mounted) return;

    await ref
        .read(matchControllerProvider.notifier)
        .applyInventory(userId, matchId, skipHaveDecrement: skipHaveDecrement);
    // Success snackbar only; failures are handled by the controller listen.
    if (mounted && !ref.read(matchControllerProvider).hasError) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.inventoryUpdatedSnack)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final matchesAsync = ref.watch(matchesProvider(user.id));
    final l10n = AppLocalizations.of(context)!;

    // Single owner for match-mutation error SnackBars (#241).
    ref.listen<AsyncValue<void>>(matchControllerProvider, (previous, next) {
      if (!next.hasError) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorPrefix(next.error.toString()))),
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.trades),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refresh,
            onPressed: () {
              ref.invalidate(matchesProvider(user.id));
              ref.invalidate(notificationCountsProvider(user.id));
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: matchesAsync.when(
            data: (matches) => TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                _buildTab(
                  l10n.tabMatch,
                  _tabCount(matches, TradeTab.match_, user.id),
                ),
                _buildTab(
                  l10n.tabOfferOut,
                  _tabCount(matches, TradeTab.offerOut, user.id),
                ),
                _buildTab(
                  l10n.tabOfferIn,
                  _tabCount(matches, TradeTab.offerIn, user.id),
                ),
                _buildTab(
                  l10n.tabActive,
                  _tabCount(matches, TradeTab.active, user.id),
                ),
                _buildTab(
                  l10n.tabDone,
                  _tabCount(matches, TradeTab.completed, user.id),
                ),
              ],
            ),
            loading: () => TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: l10n.tabMatch),
                Tab(text: l10n.tabOfferOut),
                Tab(text: l10n.tabOfferIn),
                Tab(text: l10n.tabActive),
                Tab(text: l10n.tabDone),
              ],
            ),
            error: (_, _) => TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: l10n.tabMatch),
                Tab(text: l10n.tabOfferOut),
                Tab(text: l10n.tabOfferIn),
                Tab(text: l10n.tabActive),
                Tab(text: l10n.tabDone),
              ],
            ),
          ),
        ),
      ),
      body: matchesAsync.when(
        data: (matches) => TabBarView(
          controller: _tabController,
          children: TradeTab.values.map((tab) {
            final filtered = _filterMatches(matches, tab, user.id);
            if (filtered.isEmpty) return _buildEmptyState(context, tab);
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final match = filtered[index];
                return TradeMatchCard(
                  user: user,
                  match: match,
                  tab: tab,
                  onOpenChat: () => context.go('/matches/chat/${match.id}'),
                  onUpdateStatus: (status) =>
                      _updateStatus(user.id, match.id, status),
                  onMakeOffer: () => _showOfferDialog(user, match),
                  onApplyInventory: () => _applyInventory(user.id, match.id),
                );
              },
            );
          }).toList(),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) =>
            Center(child: Text(l10n.errorPrefix(err.toString()))),
      ),
    );
  }

  Widget _buildTab(String label, int count) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showOfferDialog(User user, TradeMatch match) {
    final l10n = AppLocalizations.of(context)!;
    final meId = user.id;
    final otherId = meId == match.user1Id ? match.user2Id : match.user1Id;

    // Candidates: give = my TRADE items (cap = receiver's want, already
    // capped by the listing query LEAST); receive = other's TRADE items I
    // want (cap = my want).
    final giveItems = match.userHaves;
    final receiveItems = match.userWants;

    // Selection state, pre-filled from existing legs (counter-offer).
    final giveOn = <int, bool>{};
    final giveQty = <int, int>{};
    final giveInitially = <int>{};
    final receiveOn = <int, bool>{};
    final receiveQty = <int, int>{};
    final receiveInitially = <int>{};
    for (final leg in match.selectedItems) {
      if (leg.giverUserId == meId) {
        giveOn[leg.merchId] = true;
        giveQty[leg.merchId] = leg.quantity;
        giveInitially.add(leg.merchId);
      } else {
        receiveOn[leg.merchId] = true;
        receiveQty[leg.merchId] = leg.quantity;
        receiveInitially.add(leg.merchId);
      }
    }
    for (final i in giveItems) {
      giveOn.putIfAbsent(i.merchId, () => false);
      giveQty.putIfAbsent(i.merchId, () => 1);
    }
    for (final i in receiveItems) {
      receiveOn.putIfAbsent(i.merchId, () => false);
      receiveQty.putIfAbsent(i.merchId, () => 1);
    }

    // Projected per-side totals after applying the dialog edits to the
    // existing legs. Both sections are always shown (#303); the accumulating
    // partial-update still holds because only checked legs are submitted.
    (int, int) projectedTotals() {
      final give = <int, int>{};
      final recv = <int, int>{};
      for (final leg in match.selectedItems) {
        if (leg.giverUserId == meId) {
          give[leg.merchId] = leg.quantity;
        } else {
          recv[leg.merchId] = leg.quantity;
        }
      }
      for (final i in giveItems) {
        if (giveOn[i.merchId] == true) {
          give[i.merchId] = giveQty[i.merchId] ?? 1;
        } else if (giveInitially.contains(i.merchId)) {
          give[i.merchId] = 0;
        }
      }
      for (final i in receiveItems) {
        if (receiveOn[i.merchId] == true) {
          recv[i.merchId] = receiveQty[i.merchId] ?? 1;
        } else if (receiveInitially.contains(i.merchId)) {
          recv[i.merchId] = 0;
        }
      }
      final g = give.values.fold(0, (a, b) => a + b);
      final r = recv.values.fold(0, (a, b) => a + b);
      return (g, r);
    }

    List<OfferItem> buildItems() {
      final items = <OfferItem>[];
      for (final i in giveItems) {
        if (giveOn[i.merchId] == true) {
          items.add(
            OfferItem()
              ..merchId = i.merchId
              ..giverUserId = meId
              ..quantity = giveQty[i.merchId] ?? 1,
          );
        } else if (giveInitially.contains(i.merchId)) {
          // Uncheck a prefilled leg → remove it (qty 0, accumulating).
          items.add(
            OfferItem()
              ..merchId = i.merchId
              ..giverUserId = meId
              ..quantity = 0,
          );
        }
      }
      for (final i in receiveItems) {
        if (receiveOn[i.merchId] == true) {
          items.add(
            OfferItem()
              ..merchId = i.merchId
              ..giverUserId = otherId
              ..quantity = receiveQty[i.merchId] ?? 1,
          );
        } else if (receiveInitially.contains(i.merchId)) {
          items.add(
            OfferItem()
              ..merchId = i.merchId
              ..giverUserId = otherId
              ..quantity = 0,
          );
        }
      }
      return items;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final items = buildItems();
          final hasChange = items.isNotEmpty;
          final (g, r) = projectedTotals();
          final balanced = g == r && g > 0;
          final legCount = items.where((i) => i.quantity > 0).length;

          return AlertDialog(
            title: Text(l10n.makeTradeOffer),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        balanced ? Icons.balance : Icons.error_outline,
                        size: 16,
                        color: balanced ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.balanceSummary(g, r),
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        balanced ? l10n.balanced : l10n.unbalanced,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: balanced ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.balanceExplanation,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  if (giveItems.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.itemsYouGive,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...giveItems.map(
                      (item) => _legRow(
                        item: item,
                        selected: giveOn[item.merchId] ?? false,
                        qty: giveQty[item.merchId] ?? 1,
                        onToggle: (v) => setDialogState(
                          () => giveOn[item.merchId] = v ?? false,
                        ),
                        onQty: (q) =>
                            setDialogState(() => giveQty[item.merchId] = q),
                      ),
                    ),
                  ],
                  if (receiveItems.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.itemsYouReceive,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...receiveItems.map(
                      (item) => _legRow(
                        item: item,
                        selected: receiveOn[item.merchId] ?? false,
                        qty: receiveQty[item.merchId] ?? 1,
                        onToggle: (v) => setDialogState(
                          () => receiveOn[item.merchId] = v ?? false,
                        ),
                        onQty: (q) =>
                            setDialogState(() => receiveQty[item.merchId] = q),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                onPressed: hasChange
                    ? () {
                        Navigator.pop(ctx);
                        _submitOffer(meId, match.id, items);
                      }
                    : null,
                child: Text(l10n.sendOfferItems(legCount)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _legRow({
    required InventoryItem item,
    required bool selected,
    required int qty,
    required ValueChanged<bool?> onToggle,
    required ValueChanged<int> onQty,
  }) {
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

  Widget _buildEmptyState(BuildContext context, TradeTab tab) {
    final l10n = AppLocalizations.of(context)!;
    String message;
    switch (tab) {
      case TradeTab.match_:
        message = l10n.noPendingMatches;
      case TradeTab.offerOut:
        message = l10n.noOutgoingOffers;
      case TradeTab.offerIn:
        message = l10n.noIncomingOffers;
      case TradeTab.active:
        message = l10n.noActiveTrades;
      case TradeTab.completed:
        message = l10n.noCompletedTrades;
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swap_horiz, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(fontSize: 15, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
