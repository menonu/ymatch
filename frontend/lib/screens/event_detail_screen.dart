import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'add_merch_screen.dart';

enum ViewMode { detailed, grid, list }

final viewModeProvider = StateProvider<ViewMode>((ref) => ViewMode.detailed);

enum MerchFilter { all, have, want, missing }

final merchFilterProvider = StateProvider<MerchFilter>(
  (ref) => MerchFilter.all,
);

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

    return merchAsync.when(
      data: (merch) {
        if (merch.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Event Inventory')),
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
          if (filterMode == MerchFilter.all) return true;
          final inv = inventoryLookup[item.id] ?? {};
          final have = inv['HAVE'] ?? 0;
          final want = inv['WANT'] ?? 0;

          if (filterMode == MerchFilter.have) return have > 0;
          if (filterMode == MerchFilter.want) return want > 0;
          if (filterMode == MerchFilter.missing) return have == 0 && want == 0;
          return true;
        }).toList();

        // Group the merchandise
        final groupedMerch = <String, List<Merchandise>>{};
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
          return a.compareTo(b);
        });

        return DefaultTabController(
          length: groupKeys.length,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Event Inventory'),
              actions: [
                IconButton(
                  icon: Icon(
                    viewMode == ViewMode.detailed
                        ? Icons.view_agenda_outlined
                        : viewMode == ViewMode.grid
                        ? Icons.grid_view
                        : Icons.view_list,
                  ),
                  tooltip: 'Switch View Mode',
                  onPressed: () {
                    final next = ViewMode
                        .values[(viewMode.index + 1) % ViewMode.values.length];
                    ref.read(viewModeProvider.notifier).state = next;
                  },
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
                      for (final item in merch) {
                        if (!ownedOrWantedIds.contains(item.id)) {
                          ref
                              .read(inventoryProvider(user.id).notifier)
                              .updateItem(item.id, 'WANT', 1);
                          addedCount++;
                        }
                      }

                      if (context.mounted && addedCount > 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Added $addedCount missing items to WANT',
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
              bottom: TabBar(
                isScrollable: true,
                tabs: groupKeys.map((name) => Tab(text: name)).toList(),
              ),
            ),
            body: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<MerchFilter>(
                      segments: const [
                        ButtonSegment(
                          value: MerchFilter.all,
                          label: Text('All'),
                        ),
                        ButtonSegment(
                          value: MerchFilter.have,
                          label: Text('HAVE'),
                        ),
                        ButtonSegment(
                          value: MerchFilter.want,
                          label: Text('WANT'),
                        ),
                        ButtonSegment(
                          value: MerchFilter.missing,
                          label: Text('Missing'),
                        ),
                      ],
                      selected: {filterMode},
                      onSelectionChanged: (Set<MerchFilter> newSelection) {
                        ref.read(merchFilterProvider.notifier).state =
                            newSelection.first;
                      },
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: groupKeys.map((groupName) {
                      final items = groupedMerch[groupName]!;

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
                                childAspectRatio: 0.55,
                              ),
                          itemCount: items.length,
                          itemBuilder: (context, index) => _buildGridItem(
                            context,
                            ref,
                            user,
                            items[index],
                            inventoryLookup,
                          ),
                        );
                      } else if (viewMode == ViewMode.list) {
                        return ListView.builder(
                          padding: const EdgeInsets.only(top: 8, bottom: 80),
                          itemCount: items.length,
                          itemBuilder: (context, index) =>
                              _buildCompactListItem(
                                context,
                                ref,
                                user,
                                items[index],
                                inventoryLookup,
                              ),
                        );
                      } else {
                        return ReorderableListView.builder(
                          padding: const EdgeInsets.only(
                            top: 16,
                            bottom: 80,
                            left: 16,
                            right: 16,
                          ),
                          itemCount: items.length,
                          onReorder: (oldIndex, newIndex) {
                            if (oldIndex < newIndex) newIndex -= 1;
                            final item = items.removeAt(oldIndex);
                            items.insert(newIndex, item);

                            // Calculate new sort orders
                            final Map<int, int> newSortOrders = {};
                            for (int i = 0; i < items.length; i++) {
                              newSortOrders[items[i].id] = i;
                            }

                            // Optimistically update DB
                            ref
                                .read(merchControllerProvider.notifier)
                                .updateSortOrder(widget.eventId, newSortOrders);
                          },
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return Container(
                              key: ValueKey(item.id),
                              child: _buildDetailedListItem(
                                context,
                                ref,
                                user,
                                item,
                                inventoryLookup,
                              ),
                            );
                          },
                        );
                      }
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
  ) {
    final merchInv = lookup[item.id] ?? {};
    final haveQty = merchInv['HAVE'] ?? 0;
    final wantQty = merchInv['WANT'] ?? 0;
    final tradeQty = merchInv['TRADE'] ?? 0;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: item.hasPhotoUrl() && item.photoUrl.isNotEmpty
                ? Image.network(
                    item.photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildGridPlaceholder(),
                  )
                : _buildGridPlaceholder(),
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
              Expanded(
                child: _buildGridCounter(
                  context,
                  'H',
                  haveQty,
                  AppTheme.haveColor,
                  (q) => _updateInv(ref, user, item.id, 'HAVE', q),
                ),
              ),
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
          ),
        ],
      ),
    );
  }

  Widget _buildGridPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: Icon(Icons.image_outlined, size: 24, color: Colors.grey[400]),
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
  ) {
    final merchInv = lookup[item.id] ?? {};
    final haveQty = merchInv['HAVE'] ?? 0;
    final wantQty = merchInv['WANT'] ?? 0;
    final tradeQty = merchInv['TRADE'] ?? 0;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: item.hasPhotoUrl() && item.photoUrl.isNotEmpty
              ? Image.network(
                  item.photoUrl,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildCompactPlaceholder(),
                )
              : _buildCompactPlaceholder(),
        ),
        title: Text(
          item.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        trailing: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCompactCounter(
                context,
                'HAVE',
                haveQty,
                AppTheme.haveColor,
                (q) => _updateInv(ref, user, item.id, 'HAVE', q),
              ),
              const SizedBox(width: 8),
              _buildCompactCounter(
                context,
                'WANT',
                wantQty,
                AppTheme.wantColor,
                (q) => _updateInv(ref, user, item.id, 'WANT', q),
              ),
              const SizedBox(width: 8),
              _buildCompactCounter(
                context,
                'TRADE',
                tradeQty,
                AppTheme.tradeColor,
                (q) => _updateInv(ref, user, item.id, 'TRADE', q),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactPlaceholder() {
    return Container(
      width: 40,
      height: 40,
      color: Colors.grey[200],
      child: Icon(Icons.image_outlined, size: 20, color: Colors.grey[400]),
    );
  }

  Widget _buildCompactCounter(
    BuildContext context,
    String label,
    int qty,
    Color color,
    Function(int) onUpdate,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label[0],
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 4),
        Container(
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove, size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28),
                color: color,
                onPressed: qty > 0 ? () => onUpdate(qty - 1) : null,
              ),
              Text(
                '$qty',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28),
                color: color,
                onPressed: () => onUpdate(qty + 1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Detailed List View Item (Original) ---
  Widget _buildDetailedListItem(
    BuildContext context,
    WidgetRef ref,
    User? user,
    Merchandise item,
    Map<int, Map<String, int>> lookup,
  ) {
    final merchInv = lookup[item.id] ?? {};
    final haveQty = merchInv['HAVE'] ?? 0;
    final wantQty = merchInv['WANT'] ?? 0;
    final tradeQty = merchInv['TRADE'] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: item.hasPhotoUrl() && item.photoUrl.isNotEmpty
                  ? Image.network(
                      item.photoUrl,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildImagePlaceholder(),
                    )
                  : _buildImagePlaceholder(),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildStepper(
                        label: 'HAVE',
                        color: AppTheme.haveColor,
                        qty: haveQty,
                        onUpdate: (q) =>
                            _updateInv(ref, user, item.id, 'HAVE', q),
                      ),
                      _buildStepper(
                        label: 'WANT',
                        color: AppTheme.wantColor,
                        qty: wantQty,
                        onUpdate: (q) =>
                            _updateInv(ref, user, item.id, 'WANT', q),
                      ),
                      _buildStepper(
                        label: 'TRADE',
                        color: AppTheme.tradeColor,
                        qty: tradeQty,
                        onUpdate: (q) =>
                            _updateInv(ref, user, item.id, 'TRADE', q),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updateInv(
    WidgetRef ref,
    User? user,
    int merchId,
    String status,
    int qty,
  ) {
    if (user != null) {
      ref
          .read(inventoryProvider(user.id).notifier)
          .updateItem(merchId, status, qty);
    }
  }

  // ... rest of the helpers
  Widget _buildImagePlaceholder() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.image_outlined, size: 32, color: Colors.grey[400]),
    );
  }

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
      width:
          100, // Fixed width to ensure it doesn't squish too much and looks uniform in Wrap
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepperButton(
                icon: Icons.remove,
                color: color,
                onTap: qty > 0 ? () => onUpdate(qty - 1) : null,
                label: 'Decrease $label',
              ),
              Expanded(
                child: Text(
                  '$qty',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _StepperButton(
                icon: Icons.add,
                color: color,
                onTap: () => onUpdate(qty + 1),
                label: 'Increase $label',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String label;

  const _StepperButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    return Semantics(
      label: label,
      button: true,
      enabled: isEnabled,
      child: Material(
        color: isEnabled ? color : Colors.grey[300],
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(
              icon,
              color: isEnabled ? Colors.white : Colors.grey[500],
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}
