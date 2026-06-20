import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../services/api_client.dart';
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

  Future<void> _updateStatus(int userId, int matchId, String newStatus) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final client = ref.read(apiClientProvider);
      final payload = UpdateMatchStatusRequest()..status = newStatus;
      await client.post(
        '/api/v1/matches/$matchId/status',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      ref.invalidate(matchesProvider(userId));
      ref.invalidate(notificationCountsProvider(userId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.errorPrefix(e.toString()))));
      }
    }
  }

  Future<void> _submitOffer(
    int userId,
    int matchId,
    List<OfferItem> items,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final client = ref.read(apiClientProvider);
      final payload = OfferTradeRequest()
        ..userId = userId
        ..items.addAll(items);
      await client.post(
        '/api/v1/matches/$matchId/offer',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      ref.invalidate(matchesProvider(userId));
      ref.invalidate(notificationCountsProvider(userId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.errorPrefix(e.toString()))));
      }
    }
  }

  Future<void> _applyInventory(int userId, int matchId) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final client = ref.read(apiClientProvider);
      final payload = ApplyInventoryRequest()..userId = userId;
      await client.post(
        '/api/v1/matches/$matchId/apply-inventory',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      ref.invalidate(matchesProvider(userId));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.inventoryUpdatedSnack)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.errorPrefix(e.toString()))));
      }
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

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.trades),
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
        onTap: (tab != TradeTab.completed)
            ? () => context.go('/matches/chat/${match.id}')
            : null,
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
                      ],
                    ),
                  ),
                  if (tab != TradeTab.completed)
                    const Icon(
                      Icons.chat_bubble_outline,
                      color: Colors.grey,
                      size: 20,
                    ),
                ],
              ),

              // Items section
              if (match.selectedItems.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildSelectedItems(context, match),
              ] else if (match.userHaves.isNotEmpty ||
                  match.userWants.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildPotentialItems(context, match),
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

  Widget _buildSelectedItems(BuildContext context, TradeMatch match) {
    final l10n = AppLocalizations.of(context)!;
    final gives = match.selectedItems
        .where((i) => i.direction == 'GIVE')
        .toList();
    final receives = match.selectedItems
        .where((i) => i.direction == 'RECEIVE')
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
                fit: BoxFit.cover,
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
                onPressed: () => _updateStatus(user.id, match.id, 'ACCEPTED'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: Text(l10n.accept),
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
    // Build selectable items: user's TRADE items (give) and other's TRADE items (receive)
    final giveItems = match.userHaves; // items user can give
    final receiveItems = match.userWants; // items user can receive
    final l10n = AppLocalizations.of(context)!;

    final selectedGive = <int>{};
    final selectedReceive = <int>{};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final totalSelected = selectedGive.length + selectedReceive.length;

          return AlertDialog(
            title: Text(l10n.makeTradeOffer),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (giveItems.isNotEmpty) ...[
                    Text(
                      l10n.itemsYouGive,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...giveItems.map(
                      (item) => CheckboxListTile(
                        dense: true,
                        title: Text(
                          item.merchName,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          l10n.qtyLabel(item.quantity),
                          style: const TextStyle(fontSize: 12),
                        ),
                        value: selectedGive.contains(item.merchId),
                        activeColor: AppTheme.tradeColor,
                        onChanged: (v) => setDialogState(() {
                          if (v == true) {
                            selectedGive.add(item.merchId);
                          } else {
                            selectedGive.remove(item.merchId);
                          }
                        }),
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
                      (item) => CheckboxListTile(
                        dense: true,
                        title: Text(
                          item.merchName,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          l10n.qtyLabel(item.quantity),
                          style: const TextStyle(fontSize: 12),
                        ),
                        value: selectedReceive.contains(item.merchId),
                        activeColor: AppTheme.wantColor,
                        onChanged: (v) => setDialogState(() {
                          if (v == true) {
                            selectedReceive.add(item.merchId);
                          } else {
                            selectedReceive.remove(item.merchId);
                          }
                        }),
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
                onPressed: totalSelected > 0
                    ? () {
                        final items = <OfferItem>[];
                        for (final merchId in selectedGive) {
                          final inv = giveItems.firstWhere(
                            (i) => i.merchId == merchId,
                          );
                          items.add(
                            OfferItem()
                              ..merchId = merchId
                              ..direction = 'GIVE'
                              ..quantity = inv.quantity,
                          );
                        }
                        for (final merchId in selectedReceive) {
                          final inv = receiveItems.firstWhere(
                            (i) => i.merchId == merchId,
                          );
                          items.add(
                            OfferItem()
                              ..merchId = merchId
                              ..direction = 'RECEIVE'
                              ..quantity = inv.quantity,
                          );
                        }
                        Navigator.pop(ctx);
                        _submitOffer(user.id, match.id, items);
                      }
                    : null,
                child: Text(l10n.sendOfferItems(totalSelected)),
              ),
            ],
          );
        },
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
