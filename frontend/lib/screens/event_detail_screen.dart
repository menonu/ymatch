import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/image_helper.dart';
import 'add_merch_screen.dart';

enum ViewMode { detailed, grid, list }

final viewModeProvider = StateProvider<ViewMode>((ref) => ViewMode.detailed);

enum MerchFilter { all, have, want, missing }

final merchFilterProvider = StateProvider<MerchFilter>(
  (ref) => MerchFilter.all,
);

enum InventoryDisplayMode { have, wantTrade, all }

final inventoryDisplayModeProvider = StateProvider<InventoryDisplayMode>(
  (ref) => InventoryDisplayMode.all,
);

final itemSearchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

class EventDetailScreen extends ConsumerStatefulWidget {
  final int eventId;

  const EventDetailScreen({super.key, required this.eventId});

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Register the view when the screen is opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        ref
            .read(eventsControllerProvider.notifier)
            .registerView(widget.eventId, user.id);
        // We do not invalidate immediately to avoid jitter, it will refresh next time Home is opened.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final merchAsync = ref.watch(merchProvider(widget.eventId));
    final user = ref.watch(currentUserProvider);
    final inventoryAsync = user != null
        ? ref.watch(inventoryProvider(user.id))
        : null;
    final viewMode = ref.watch(viewModeProvider);
    final filterMode = ref.watch(merchFilterProvider);
    final displayMode = ref.watch(inventoryDisplayModeProvider);
    final searchQuery = ref.watch(itemSearchQueryProvider);

    return merchAsync.when(
      data: (merch) {
        if (merch.isEmpty) {
          return Scaffold(
            appBar: AppBar(),
            body: _buildEmptyState(context, ref),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AddMerchScreen(eventId: widget.eventId),
                    fullscreenDialog: true,
                  ),
                );
              },
              label: const Text('Add Merch'),
              icon: const Icon(Icons.add_photo_alternate),
            ),
          );
        }

        final Map<int, Map<String, int>> inventoryLookup = {};
        if (inventoryAsync != null && inventoryAsync.hasValue) {
          for (final inv in inventoryAsync.value!) {
            inventoryLookup.putIfAbsent(inv.merchId, () => {})[inv.status] =
                inv.quantity;
          }
        }

        // Apply Filter
        final filteredMerch = merch.where((item) {
          if (searchQuery.isNotEmpty &&
              !item.name.toLowerCase().contains(searchQuery.toLowerCase())) {
            return false;
          }

          if (filterMode == MerchFilter.all) return true;
          final inv = inventoryLookup[item.id] ?? {};
          final have = inv['HAVE'] ?? 0;
          final want = inv['WANT'] ?? 0;

          if (filterMode == MerchFilter.have) return have > 0;
          if (filterMode == MerchFilter.want) return want > 0;
          if (filterMode == MerchFilter.missing) return have == 0 && want == 0;
          return true;
        }).toList();

        final hiddenCount = merch.length - filteredMerch.length;

        // Build group keys from ALL merch (so groups are always visible)
        final allGroupKeys = <String>{};
        for (final item in merch) {
          final gName = item.hasGroupName() && item.groupName.isNotEmpty
              ? item.groupName
              : 'Other Items';
          allGroupKeys.add(gName);
        }

        // Group the filtered merchandise
        final groupedMerch = <String, List<Merchandise>>{};
        for (final gName in allGroupKeys) {
          groupedMerch[gName] = [];
        }
        for (final item in filteredMerch) {
          final gName = item.hasGroupName() && item.groupName.isNotEmpty
              ? item.groupName
              : 'Other Items';
          groupedMerch.putIfAbsent(gName, () => []).add(item);
        }

        final groupKeys = groupedMerch.keys.toList();
        groupKeys.sort((a, b) {
          if (a == 'Other Items') return 1;
          if (b == 'Other Items') return -1;
          return _naturalCompare(a, b);
        });
        // Natural sort items within each group
        for (final items in groupedMerch.values) {
          items.sort((a, b) => _naturalCompare(a.name, b.name));
        }

        return DefaultTabController(
          length: groupKeys.length,
          child: Scaffold(
            appBar: AppBar(
              titleSpacing: 16,
              title: SizedBox(
                height: 40,
                child: SearchBar(
                  elevation: WidgetStateProperty.all(0),
                  backgroundColor: WidgetStateProperty.all(Colors.grey[200]),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  hintText: 'Search items...',
                  leading: const Icon(Icons.search, size: 20),
                  trailing: [
                    if (searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          ref.read(itemSearchQueryProvider.notifier).state = '';
                        },
                      ),
                  ],
                  onChanged: (value) {
                    ref.read(itemSearchQueryProvider.notifier).state = value;
                  },
                ),
              ),
              actions: [
                // Refresh button
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                  onPressed: () {
                    ref.invalidate(merchProvider(widget.eventId));
                    if (user != null) ref.invalidate(inventoryProvider(user.id));
                  },
                ),
                // Show controls (display mode) moved to AppBar
                PopupMenuButton<InventoryDisplayMode>(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.visibility),
                      if (displayMode != InventoryDisplayMode.all)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  tooltip: 'Show Controls',
                  onSelected: (InventoryDisplayMode result) {
                    ref.read(inventoryDisplayModeProvider.notifier).state = result;
                  },
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem<InventoryDisplayMode>(
                      value: InventoryDisplayMode.have,
                      child: Text('Just HAVE'),
                    ),
                    const PopupMenuItem<InventoryDisplayMode>(
                      value: InventoryDisplayMode.wantTrade,
                      child: Text('WANT & TRADE'),
                    ),
                    const PopupMenuItem<InventoryDisplayMode>(
                      value: InventoryDisplayMode.all,
                      child: Text('All'),
                    ),
                  ],
                ),
                PopupMenuButton<ViewMode>(
                  icon: const Icon(Icons.view_agenda),
                  tooltip: 'Change View Mode',
                  onSelected: (ViewMode result) {
                    ref.read(viewModeProvider.notifier).state = result;
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<ViewMode>>[
                        const PopupMenuItem<ViewMode>(
                          value: ViewMode.detailed,
                          child: Row(
                            children: [
                              Icon(Icons.view_agenda_outlined, size: 20),
                              SizedBox(width: 12),
                              Text('Detailed View'),
                            ],
                          ),
                        ),
                        const PopupMenuItem<ViewMode>(
                          value: ViewMode.grid,
                          child: Row(
                            children: [
                              Icon(Icons.grid_view, size: 20),
                              SizedBox(width: 12),
                              Text('Grid View'),
                            ],
                          ),
                        ),
                        const PopupMenuItem<ViewMode>(
                          value: ViewMode.list,
                          child: Row(
                            children: [
                              Icon(Icons.view_list, size: 20),
                              SizedBox(width: 12),
                              Text('Compact List'),
                            ],
                          ),
                        ),
                      ],
                ),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'want_missing') {
                      if (user == null) return;

                      final currentInv = inventoryAsync?.valueOrNull ?? [];
                      final ownedOrWantedIds = currentInv
                          .where((inv) => inv.quantity > 0)
                          .map((inv) => inv.merchId)
                          .toSet();

                      int addedCount = 0;
                      int failedCount = 0;
                      for (final item in merch) {
                        if (!ownedOrWantedIds.contains(item.id)) {
                          // Await each call so the count reflects what was
                          // actually saved: updateItem rethrows on failure
                          // (#239), so a failed POST doesn't count as added.
                          try {
                            await ref
                                .read(inventoryProvider(user.id).notifier)
                                .updateItem(item.id, 'WANT', 1);
                            addedCount++;
                          } catch (_) {
                            failedCount++;
                          }
                        }
                      }

                      if (context.mounted && addedCount > 0 && failedCount > 0) {
                        // Partial failure: surface both counts so the user
                        // knows not everything was saved (#239).
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Added $addedCount to WANT; '
                              'could not add $failedCount',
                            ),
                          ),
                        );
                      } else if (context.mounted && addedCount > 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Added $addedCount missing items to WANT',
                            ),
                          ),
                        );
                      } else if (context.mounted && failedCount > 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not add some items to WANT',
                            ),
                          ),
                        );
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No missing items found'),
                          ),
                        );
                      }
                    }
                  },
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem(
                      value: 'want_missing',
                      child: Text('Want All Missing'),
                    ),
                  ],
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(kTextTabBarHeight),
                child: Builder(
                  builder: (context) {
                    final tabCtrl = DefaultTabController.of(context);
                    return Row(
                      children: [
                        // Group jump dropdown
                        PopupMenuButton<int>(
                          icon: const Icon(Icons.list, size: 20),
                          tooltip: 'Jump to group',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36),
                          onSelected: (idx) => tabCtrl.animateTo(idx),
                          itemBuilder: (_) => groupKeys.asMap().entries.map((e) {
                            return PopupMenuItem<int>(
                              value: e.key,
                              child: Text(e.value),
                            );
                          }).toList(),
                        ),
                        Expanded(
                          child: TabBar(
                            isScrollable: true,
                            tabs: groupKeys.map((name) {
                              return Tab(
                                child: Consumer(
                                  builder: (context, ref, _) {
                                    final favGroups =
                                        ref.watch(favoriteGroupsProvider).valueOrNull ?? [];
                                    final isFav = favGroups.any(
                                      (g) =>
                                          g.eventId == widget.eventId &&
                                          g.groupName == name,
                                    );
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(name),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                          onTap: user == null
                                              ? null
                                              : () async {
                                                  await ref
                                                      .read(eventsControllerProvider.notifier)
                                                      .toggleFavoriteGroup(
                                                        widget.eventId,
                                                        user.id,
                                                        name,
                                                        !isFav,
                                                      );
                                                  ref.invalidate(favoriteGroupsProvider);
                                                },
                                          child: Icon(
                                            isFav ? Icons.star : Icons.star_border,
                                            color: Colors.amber,
                                            size: 18,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            body: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<MerchFilter>(
                            segments: const [
                              ButtonSegment(
                                value: MerchFilter.all,
                                label: Text('All'),
                                icon: Icon(Icons.inventory_2_outlined, size: 16),
                              ),
                              ButtonSegment(
                                value: MerchFilter.have,
                                label: Text('HAVE'),
                                icon: Icon(Icons.check_circle_outline, size: 16),
                              ),
                              ButtonSegment(
                                value: MerchFilter.want,
                                label: Text('WANT'),
                                icon: Icon(Icons.favorite_border, size: 16),
                              ),
                              ButtonSegment(
                                value: MerchFilter.missing,
                                label: Text('Missing'),
                                icon: Icon(Icons.help_outline, size: 16),
                              ),
                            ],
                            selected: {filterMode},
                            onSelectionChanged: (Set<MerchFilter> newSelection) {
                              ref.read(merchFilterProvider.notifier).state =
                                  newSelection.first;
                            },
                            style: SegmentedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              textStyle: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      ),
                      if (hiddenCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$hiddenCount hidden',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: groupKeys.map((groupName) {
                      final items = groupedMerch[groupName]!;

                      return Column(
                        children: [
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                if (items.isEmpty) {
                                  return const Center(
                                    child: Text(
                                      'No items match this filter.',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  );
                                }

                                if (viewMode == ViewMode.grid) {
                                  return GridView.builder(
                                    padding: const EdgeInsets.only(
                                      top: 16,
                                      bottom: 80,
                                      left: 16,
                                      right: 16,
                                    ),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 3,
                                          crossAxisSpacing: 8,
                                          mainAxisSpacing: 8,
                                          childAspectRatio: 0.6,
                                        ),
                                    itemCount: items.length,
                                    itemBuilder: (context, index) =>
                                        _buildGridItem(
                                          context,
                                          ref,
                                          user,
                                          items[index],
                                          inventoryLookup,
                                          displayMode,
                                        ),
                                  );
                                } else if (viewMode == ViewMode.list) {
                                  return ListView.builder(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                      bottom: 80,
                                    ),
                                    itemCount: items.length,
                                    itemBuilder: (context, index) =>
                                        _buildCompactListItem(
                                          context,
                                          ref,
                                          user,
                                          items[index],
                                          inventoryLookup,
                                          displayMode,
                                        ),
                                  );
                                } else {
                                  // #203: removed ReorderableListView +
                                  // updateSortOrder; manual item sorting
                                  // conflicted with the inventory steppers.
                                  return ListView.builder(
                                    padding: const EdgeInsets.only(
                                      top: 16,
                                      bottom: 80,
                                      left: 16,
                                      right: 16,
                                    ),
                                    itemCount: items.length,
                                    itemBuilder: (context, index) {
                                      final item = items[index];
                                      return _buildDetailedListItem(
                                        context,
                                        ref,
                                        user,
                                        item,
                                        inventoryLookup,
                                        displayMode,
                                      );
                                    },
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AddMerchScreen(eventId: widget.eventId),
                    fullscreenDialog: true,
                  ),
                );
              },
              label: const Text('Add Merch'),
              icon: const Icon(Icons.add_photo_alternate),
            ),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, stack) => Scaffold(body: Center(child: Text('Error: $err'))),
    );
  }

  // --- Grid View Item ---
  Widget _buildGridItem(
    BuildContext context,
    WidgetRef ref,
    User? user,
    Merchandise item,
    Map<int, Map<String, int>> lookup,
    InventoryDisplayMode displayMode,
  ) {
    final merchInv = lookup[item.id] ?? {};
    final haveQty = merchInv['HAVE'] ?? 0;
    final wantQty = merchInv['WANT'] ?? 0;
    final tradeQty = merchInv['TRADE'] ?? 0;

    final showHave =
        displayMode == InventoryDisplayMode.have ||
        displayMode == InventoryDisplayMode.all;
    final showWantTrade =
        displayMode == InventoryDisplayMode.wantTrade ||
        displayMode == InventoryDisplayMode.all;

    final isOwner = user != null &&
        item.hasCreatorId() &&
        item.creatorId == user.id;

    return GestureDetector(
      onLongPress: isOwner
          ? () => _showMerchActions(context, ref, item)
          : null,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: buildImage(
                      item.hasPhotoUrl() ? item.photoUrl : null,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (isOwner)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Icon(Icons.edit_note, size: 14, color: Colors.blue[400]),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              item.name,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          Row(
            children: [
              if (showHave)
                Expanded(
                  child: _buildGridCounter(
                    context,
                    'H',
                    haveQty,
                    AppTheme.haveColor,
                    (q) => _updateInv(ref, user, item.id, 'HAVE', q),
                  ),
                ),
              if (showWantTrade) ...[
                Expanded(
                  child: _buildGridCounter(
                    context,
                    'W',
                    wantQty,
                    AppTheme.wantColor,
                    (q) => _updateInv(ref, user, item.id, 'WANT', q),
                  ),
                ),
                Expanded(
                  child: _buildGridCounter(
                    context,
                    'T',
                    tradeQty,
                    AppTheme.tradeColor,
                    (q) => _updateInv(ref, user, item.id, 'TRADE', q),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildGridCounter(
    BuildContext context,
    String label,
    int qty,
    Color color,
    Function(int) onUpdate,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: qty > 0 ? color.withValues(alpha: 0.1) : Colors.transparent,
        border: Border(
          top: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 8,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: InkWell(
                  onTap: qty > 0 ? () => onUpdate(qty - 1) : null,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Icon(
                      Icons.remove,
                      size: 12,
                      color: qty > 0 ? color : Colors.grey,
                    ),
                  ),
                ),
              ),
              Text(
                '$qty',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: qty > 0 ? color : Colors.grey,
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => onUpdate(qty + 1),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Icon(Icons.add, size: 12, color: color),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Compact List View Item ---
  Widget _buildCompactListItem(
    BuildContext context,
    WidgetRef ref,
    User? user,
    Merchandise item,
    Map<int, Map<String, int>> lookup,
    InventoryDisplayMode displayMode,
  ) {
    final merchInv = lookup[item.id] ?? {};
    final haveQty = merchInv['HAVE'] ?? 0;
    final wantQty = merchInv['WANT'] ?? 0;
    final tradeQty = merchInv['TRADE'] ?? 0;

    final showHave =
        displayMode == InventoryDisplayMode.have ||
        displayMode == InventoryDisplayMode.all;
    final showWantTrade =
        displayMode == InventoryDisplayMode.wantTrade ||
        displayMode == InventoryDisplayMode.all;

    final isOwner = user != null &&
        item.hasCreatorId() &&
        item.creatorId == user.id;

    return GestureDetector(
      onLongPress: isOwner
          ? () => _showMerchActions(context, ref, item)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: buildImage(
                item.hasPhotoUrl() ? item.photoUrl : null,
                width: 28,
                height: 28,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isOwner)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.edit_note, size: 14, color: Colors.blue[400]),
              ),
            if (showHave)
              _buildCompactCounter(
                context,
                'HAVE',
                haveQty,
                AppTheme.haveColor,
                (q) => _updateInv(ref, user, item.id, 'HAVE', q),
              ),
            if (showHave && showWantTrade) const SizedBox(width: 4),
            if (showWantTrade) ...[
              _buildCompactCounter(
                context,
                'WANT',
                wantQty,
                AppTheme.wantColor,
                (q) => _updateInv(ref, user, item.id, 'WANT', q),
              ),
              const SizedBox(width: 4),
              _buildCompactCounter(
                context,
                'TRADE',
                tradeQty,
                AppTheme.tradeColor,
                (q) => _updateInv(ref, user, item.id, 'TRADE', q),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompactCounter(
    BuildContext context,
    String label,
    int qty,
    Color color,
    Function(int) onUpdate,
  ) {
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: qty > 0 ? () => onUpdate(qty - 1) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.remove, size: 12,
                color: qty > 0 ? color : Colors.grey[400]),
            ),
          ),
          Text(
            '${label[0]}$qty',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          InkWell(
            onTap: () => onUpdate(qty + 1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.add, size: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }

  // --- Detailed List View Item (Original) ---
  Widget _buildDetailedListItem(
    BuildContext context,
    WidgetRef ref,
    User? user,
    Merchandise item,
    Map<int, Map<String, int>> lookup,
    InventoryDisplayMode displayMode,
  ) {
    final merchInv = lookup[item.id] ?? {};
    final haveQty = merchInv['HAVE'] ?? 0;
    final wantQty = merchInv['WANT'] ?? 0;
    final tradeQty = merchInv['TRADE'] ?? 0;

    final showHave =
        displayMode == InventoryDisplayMode.have ||
        displayMode == InventoryDisplayMode.all;
    final showWantTrade =
        displayMode == InventoryDisplayMode.wantTrade ||
        displayMode == InventoryDisplayMode.all;

    final isOwner = user != null &&
        item.hasCreatorId() &&
        item.creatorId == user.id;

    return GestureDetector(
      onLongPress: isOwner
          ? () => _showMerchActions(context, ref, item)
          : null,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // #203: removed ReorderableDragStartListener wrapper; the
              // image is no longer a drag handle. Long-press on the
              // card (handled by the outer GestureDetector) is now the
              // only way to trigger the owner's edit/delete menu.
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: buildImage(
                    item.hasPhotoUrl() ? item.photoUrl : null,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isOwner)
                          Tooltip(
                            message: 'You created this item',
                            child: Icon(
                              Icons.edit_note,
                              size: 18,
                              color: Colors.blue[400],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (showHave)
                          Expanded(
                            flex: 5,
                            child: _buildStepper(
                              label: 'HAVE',
                              color: AppTheme.haveColor,
                              qty: haveQty,
                              onUpdate: (q) =>
                                  _updateInv(ref, user, item.id, 'HAVE', q),
                            ),
                          ),
                        if (showHave && showWantTrade) const Spacer(flex: 1),
                        if (showWantTrade) ...[
                          Expanded(
                            flex: 5,
                            child: _buildStepper(
                              label: 'WANT',
                              color: AppTheme.wantColor,
                              qty: wantQty,
                              onUpdate: (q) =>
                                  _updateInv(ref, user, item.id, 'WANT', q),
                            ),
                          ),
                          const Spacer(flex: 1),
                          Expanded(
                            flex: 5,
                            child: _buildStepper(
                              label: 'TRADE',
                              color: AppTheme.tradeColor,
                              qty: tradeQty,
                              onUpdate: (q) =>
                                  _updateInv(ref, user, item.id, 'TRADE', q),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateInv(
    WidgetRef ref,
    User? user,
    int merchId,
    String status,
    int qty,
  ) async {
    if (user != null) {
      // updateItem rethrows on failure (#239); the optimistic state is
      // rolled back inside the notifier, so the UI reverts on its own.
      // Swallow here so the +/- steppers don't surface an uncaught
      // async error; the rollback is the user-visible signal.
      try {
        await ref
            .read(inventoryProvider(user.id).notifier)
            .updateItem(merchId, status, qty);
      } catch (_) {
        // Optimistic rollback already handled by the notifier.
      }
    }
  }

  void _showMerchActions(
    BuildContext context,
    WidgetRef ref,
    Merchandise item,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Name'),
              onTap: () {
                Navigator.pop(ctx);
                _editMerchName(context, ref, item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteMerch(context, ref, item);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editMerchName(
    BuildContext context,
    WidgetRef ref,
    Merchandise item,
  ) {
    final ctrl = TextEditingController(text: item.name);
    final user = ref.read(currentUserProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Item Name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Item name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isNotEmpty && user != null) {
                await ref
                    .read(merchControllerProvider.notifier)
                    .updateMerch(item.eventId, item.id, user.id, name: newName);
                ref.invalidate(merchProvider(widget.eventId));
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteMerch(
    BuildContext context,
    WidgetRef ref,
    Merchandise item,
  ) {
    final user = ref.read(currentUserProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Are you sure you want to delete "${item.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (user != null) {
                await ref
                    .read(merchControllerProvider.notifier)
                    .deleteMerchByCreator(item.eventId, item.id, user.id);
                ref.invalidate(merchProvider(widget.eventId));
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ... rest of the helpers
  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No merchandise yet',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Add items to start building your inventory.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildStepper({
    required String label,
    required Color color,
    required int qty,
    required Function(int) onUpdate,
  }) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Tap areas: left = decrease, right = increase
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: qty > 0 ? () => onUpdate(qty - 1) : null,
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  key: Key('stepper_inc_$label'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onUpdate(qty + 1),
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
          // −/+ hint icons centered on left/right edges
          Positioned(
            left: 2,
            top: 0,
            bottom: 0,
            child: Center(
              child: Text(
                '−',
                style: TextStyle(
                  fontSize: 9,
                  color: qty > 0
                      ? color.withValues(alpha: 0.5)
                      : Colors.grey.withValues(alpha: 0.3),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Positioned(
            right: 3,
            top: 0,
            bottom: 0,
            child: Center(
              child: Text(
                '+',
                style: TextStyle(
                  fontSize: 9,
                  color: color.withValues(alpha: 0.5),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          // Centered label + quantity (non-interactive, taps pass through)
          Center(
            child: IgnorePointer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: qty > 0 ? color : Colors.grey[500],
                    ),
                  ),
                  Text(
                    '$qty',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                      color: qty > 0 ? color : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

int _naturalCompare(String a, String b) {
  final regExp = RegExp(r'(\d+)|(\D+)');
  final partsA = regExp.allMatches(a).toList();
  final partsB = regExp.allMatches(b).toList();
  for (int i = 0; i < partsA.length && i < partsB.length; i++) {
    final pa = partsA[i].group(0)!;
    final pb = partsB[i].group(0)!;
    final na = int.tryParse(pa);
    final nb = int.tryParse(pb);
    int cmp;
    if (na != null && nb != null) {
      cmp = na.compareTo(nb);
    } else {
      cmp = pa.toLowerCase().compareTo(pb.toLowerCase());
    }
    if (cmp != 0) return cmp;
  }
  return a.length.compareTo(b.length);
}
