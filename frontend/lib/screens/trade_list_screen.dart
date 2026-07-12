import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/image_helper.dart';

enum TradeTab { match_, offerOut, offerIn, active, completed }

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
    switch (tab) {
      case TradeTab.match_:
        return matches.where((m) => m.status == 'PENDING').toList();
      case TradeTab.offerOut:
        return matches
            .where((m) => m.status == 'OFFERED' && m.offeredBy == userId)
            .toList();
      case TradeTab.offerIn:
        return matches
            .where((m) => m.status == 'OFFERED' && m.offeredBy != userId)
            .toList();
      case TradeTab.active:
        return matches.where((m) => m.status == 'ACCEPTED').toList();
      case TradeTab.completed:
        return matches.where((m) => m.status == 'COMPLETED').toList();
    }
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

  Future<void> _submitOffer(
    int userId,
    int matchId,
    List<OfferItem> items,
  ) {
    return ref
        .read(matchControllerProvider.notifier)
        .submitOffer(userId, matchId, items);
  }

  Future<void> _applyInventory(int userId, int matchId) async {
    final l10n = AppLocalizations.of(context)!;
    await ref
        .read(matchControllerProvider.notifier)
        .applyInventory(userId, matchId);
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
              itemBuilder: (context, index) =>
                  _buildMatchCard(context, user, filtered[index], tab),
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

  Widget _buildMatchCard(
    BuildContext context,
    User user,
    TradeMatch match,
    TradeTab tab,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final otherName = match.hasOtherUser()
        ? match.otherUser.username
        : l10n.unknownUser;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // #314: completed matches stay conversable — the card opens the chat
        // thread on every tab, same as while trading.
        onTap: () => context.go('/matches/chat/${match.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: user + status
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppTheme.secondaryColor.withValues(
                      alpha: 0.1,
                    ),
                    child: const Icon(
                      Icons.person,
                      color: AppTheme.secondaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          otherName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        _statusChip(context, match.status),
                        // #322 / ADR 0001: a match is scoped to one item group,
                        // so show `event:group` once on the card instead of per
                        // item. Both fields are NOT NULL on a real match; guard
                        // so synthetic/test matches without them render nothing.
                        if (match.hasGroupName() && match.hasEventName()) ...[
                          const SizedBox(height: 2),
                          Text(
                            l10n.matchGroupLabel(
                              match.eventName,
                              match.groupName,
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // #314: the Message affordance is shown on every tab,
                  // including completed matches (chat remains open after a
                  // trade is done, same as while trading).
                  FilledButton.tonal(
                    onPressed: () => context.go('/matches/chat/${match.id}'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(l10n.messageAction),
                  ),
                ],
              ),

              // Items section
              if (match.selectedItems.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildSelectedItems(context, user.id, match),
              ] else if (match.userHaves.isNotEmpty ||
                  match.userWants.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildPotentialItems(context, match),
              ],

              // Balance indicator on an open proposal (#297)
              if (match.status == 'OFFERED') ...[
                const SizedBox(height: 8),
                _buildBalanceIndicator(context, user.id, match),
              ],

              // Action buttons
              ..._buildActions(context, user, match, tab),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(BuildContext context, String status) {
    final l10n = AppLocalizations.of(context)!;
    Color color;
    String label;
    switch (status) {
      case 'PENDING':
        color = Colors.orange;
        label = l10n.statusPending;
        break;
      case 'OFFERED':
        color = Colors.blue;
        label = l10n.statusOffered;
        break;
      case 'ACCEPTED':
        color = Colors.green;
        label = l10n.statusAccepted;
        break;
      case 'COMPLETED':
        color = Colors.grey;
        label = l10n.statusCompleted;
        break;
      default:
        color = Colors.grey;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildPotentialItems(BuildContext context, TradeMatch match) {
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
          _buildItemChips(match.userHaves, AppTheme.tradeColor),
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
          _buildItemChips(match.userWants, AppTheme.wantColor),
        ],
      ],
    );
  }

  Widget _buildItemChips(List<InventoryItem> items, Color color) {
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

  /// Per-side quantity totals for the current proposal legs (#297).
  /// Give = legs where the viewer is the giver; Receive = legs where the
  /// other party is the giver (the viewer receives).
  (int give, int receive) _legTotals(int userId, TradeMatch match) {
    int give = 0;
    int receive = 0;
    for (final i in match.selectedItems) {
      if (i.giverUserId == userId) {
        give += i.quantity;
      } else {
        receive += i.quantity;
      }
    }
    return (give, receive);
  }

  bool _isBalanced(int userId, TradeMatch match) {
    final (give, receive) = _legTotals(userId, match);
    return give == receive && give > 0;
  }

  Widget _buildBalanceIndicator(
    BuildContext context,
    int userId,
    TradeMatch match,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final (give, receive) = _legTotals(userId, match);
    final balanced = give == receive && give > 0;
    final color = balanced ? Colors.green : Colors.orange;
    return Row(
      children: [
        Icon(
          balanced ? Icons.balance : Icons.error_outline,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          l10n.balanceSummary(give, receive),
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
        const SizedBox(width: 8),
        Text(
          balanced ? l10n.balanced : l10n.unbalanced,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedItems(
    BuildContext context,
    int userId,
    TradeMatch match,
  ) {
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
          ...gives.map((i) => _buildMatchItemRow(i, AppTheme.tradeColor)),
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
          ...receives.map((i) => _buildMatchItemRow(i, AppTheme.wantColor)),
        ],
      ],
    );
  }

  Widget _buildMatchItemRow(MatchItem item, Color color) {
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

  List<Widget> _buildActions(
    BuildContext context,
    User user,
    TradeMatch match,
    TradeTab tab,
  ) {
    final l10n = AppLocalizations.of(context)!;
    switch (tab) {
      case TradeTab.match_:
        return [
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _updateStatus(user.id, match.id, 'REJECTED'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(l10n.reject),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _showOfferDialog(user, match),
                child: Text(l10n.makeOffer),
              ),
            ],
          ),
        ];
      case TradeTab.offerIn:
        final balanced = _isBalanced(user.id, match);
        return [
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _updateStatus(user.id, match.id, 'REJECTED'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(l10n.reject),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _showOfferDialog(user, match),
                child: Text(l10n.counterOffer),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                // Accept is the non-proposer's, only of a balanced proposal
                // (#297). The backend enforces it too; this just prevents the
                // user from trying an impossible accept.
                onPressed: balanced
                    ? () => _updateStatus(user.id, match.id, 'ACCEPTED')
                    : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: Text(balanced
                    ? l10n.accept
                    : l10n.acceptBalanceHint),
              ),
            ],
          ),
        ];
      case TradeTab.offerOut:
        return [
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _updateStatus(user.id, match.id, 'REJECTED'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(l10n.cancelOffer),
              ),
              Text(
                l10n.waitingForResponse,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
        ];
      case TradeTab.active:
        return [
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton(
                onPressed: () => _updateStatus(user.id, match.id, 'COMPLETED'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: Text(l10n.markComplete),
              ),
            ],
          ),
        ];
      case TradeTab.completed:
        final actions = <Widget>[
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
        ];
        if (!match.inventoryApplied) {
          actions.add(
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _applyInventory(user.id, match.id),
                  icon: const Icon(Icons.inventory, size: 16),
                  label: Text(l10n.updateInventory),
                ),
              ],
            ),
          );
        } else {
          actions.add(
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.check_circle, size: 16, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  l10n.inventoryUpdated,
                  style: TextStyle(color: Colors.green[700], fontSize: 13),
                ),
              ],
            ),
          );
        }
        return actions;
    }
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
                        onQty: (q) => setDialogState(
                          () => giveQty[item.merchId] = q,
                        ),
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
                        onQty: (q) => setDialogState(
                          () => receiveQty[item.merchId] = q,
                        ),
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
            onPressed: selected && qty > 1
                ? () => onQty(qty - 1)
                : null,
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
        break;
      case TradeTab.offerOut:
        message = l10n.noOutgoingOffers;
        break;
      case TradeTab.offerIn:
        message = l10n.noIncomingOffers;
        break;
      case TradeTab.active:
        message = l10n.noActiveTrades;
        break;
      case TradeTab.completed:
        message = l10n.noCompletedTrades;
        break;
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
