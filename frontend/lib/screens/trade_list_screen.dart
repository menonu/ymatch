import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/format_local_datetime.dart';
import 'trade_list/match_card.dart';
import 'trade_list/offer_dialog.dart';
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

  // #241: thin wrappers — body shape + invalidation live on MatchController.
  // #498: error/success feedback is driven by the returned Future so
  // generation-discarded concurrent failures still surface a SnackBar
  // (the shared AsyncValue slot is intentionally lossy for non-latest ops).
  void _showMatchError(Object e) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.errorPrefix(e.toString()))));
  }

  Future<void> _updateStatus(int userId, int matchId, String newStatus) async {
    try {
      await ref
          .read(matchControllerProvider.notifier)
          .updateStatus(userId, matchId, newStatus);
    } catch (e) {
      _showMatchError(e);
    }
  }

  Future<void> _submitOffer(
    int userId,
    int matchId,
    List<OfferItem> items,
  ) async {
    try {
      await ref
          .read(matchControllerProvider.notifier)
          .submitOffer(userId, matchId, items);
    } catch (e) {
      _showMatchError(e);
    }
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

    try {
      await ref
          .read(matchControllerProvider.notifier)
          .applyInventory(
            userId,
            matchId,
            skipHaveDecrement: skipHaveDecrement,
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.inventoryUpdatedSnack)));
      }
    } catch (e) {
      _showMatchError(e);
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

    // #498: mutation error SnackBars come from the Future catch paths above
    // (not ref.listen on the shared slot) so concurrent discarded failures
    // still surface feedback.

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
                  onMakeOffer: () => showTradeOfferDialog(
                    context: context,
                    user: user,
                    match: match,
                    onSubmit: (items) => _submitOffer(user.id, match.id, items),
                  ),
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
