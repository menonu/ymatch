import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/group_display.dart';
import '../utils/image_helper.dart';
import '../widgets/export_inventory_dialog.dart';
import '../widgets/how_to_trade.dart';
import '../widgets/manage_event_members_dialog.dart';
import 'add_merch_screen.dart';

enum ViewMode { detailed, grid, list }

final viewModeProvider = StateProvider<ViewMode>((ref) => ViewMode.detailed);

enum MerchFilter { all, have, want, trade, missing }

final merchFilterProvider = StateProvider<MerchFilter>(
  (ref) => MerchFilter.all,
);

enum InventoryDisplayMode { have, wantTrade, trade, all }

final inventoryDisplayModeProvider = StateProvider<InventoryDisplayMode>(
  (ref) => InventoryDisplayMode.all,
);

/// Whether [item] inventory quantities pass [filter] (#472).
///
/// [missing] keeps pre-existing semantics: HAVE == 0 && WANT == 0 (TRADE is
/// ignored). TRADE-only stock therefore still matches Missing.
bool matchesMerchFilter(
  MerchFilter filter, {
  required int have,
  required int want,
  required int trade,
}) {
  switch (filter) {
    case MerchFilter.all:
      return true;
    case MerchFilter.have:
      return have > 0;
    case MerchFilter.want:
      return want > 0;
    case MerchFilter.trade:
      return trade > 0;
    case MerchFilter.missing:
      return have == 0 && want == 0;
  }
}

/// Which inventory steppers to show for [mode] (#472).
({bool showHave, bool showWant, bool showTrade}) inventoryDisplayFlags(
  InventoryDisplayMode mode,
) {
  switch (mode) {
    case InventoryDisplayMode.have:
      return (showHave: true, showWant: false, showTrade: false);
    case InventoryDisplayMode.wantTrade:
      return (showHave: false, showWant: true, showTrade: true);
    case InventoryDisplayMode.trade:
      return (showHave: false, showWant: false, showTrade: true);
    case InventoryDisplayMode.all:
      return (showHave: true, showWant: true, showTrade: true);
  }
}

final itemSearchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

class EventDetailScreen extends ConsumerStatefulWidget {
  final int eventId;

  /// Optional group tab to select on open (favorite-group shortcut, #406).
  final String? initialGroupName;

  const EventDetailScreen({
    super.key,
    required this.eventId,
    this.initialGroupName,
  });

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

/// Index of [initialGroupName] in [groupKeys], or 0 if absent/unknown (#406).
int resolveInitialGroupTabIndex(
  List<String> groupKeys,
  String? initialGroupName,
) {
  if (groupKeys.isEmpty) return 0;
  if (initialGroupName == null || initialGroupName.isEmpty) return 0;
  final i = groupKeys.indexOf(initialGroupName);
  return i >= 0 ? i : 0;
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  /// Whether the bottom-left group description panel is open (#128).
  bool _groupInfoOpen = false;

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
    final groupsAsync = ref.watch(eventGroupsProvider(widget.eventId));
    final user = ref.watch(currentUserProvider);
    // #425: the caller's effective `group.edit` decision, used to show the
    // Edit Group button for editors/moderators/admin (not just the creator).
    // null while loading / fetch fails / not logged in — leaves button hidden
    // unless the caller is the creator (checked per-group below).
    final role = ref.watch(myEventRoleProvider(widget.eventId)).valueOrNull;
    final inventoryAsync = user != null
        ? ref.watch(inventoryProvider(user.id))
        : null;
    final viewMode = ref.watch(viewModeProvider);
    final filterMode = ref.watch(merchFilterProvider);
    final displayMode = ref.watch(inventoryDisplayModeProvider);
    final searchQuery = ref.watch(itemSearchQueryProvider);
    final l10n = AppLocalizations.of(context)!;
    final otherItems = l10n.otherItems;

    return merchAsync.when(
      data: (merch) {
        if (merch.isEmpty) {
          // #483: event member management lives on Home long-press, not here.
          return Scaffold(
            appBar: AppBar(),
            body: _buildEmptyState(context, ref),
            floatingActionButton: _buildAddMerchFab(context),
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

          final inv = inventoryLookup[item.id] ?? {};
          return matchesMerchFilter(
            filterMode,
            have: inv['HAVE'] ?? 0,
            want: inv['WANT'] ?? 0,
            trade: inv['TRADE'] ?? 0,
          );
        }).toList();

        final hiddenCount = merch.length - filteredMerch.length;

        // Build group keys from ALL merch (so groups are always visible)
        final allGroupKeys = <String>{};
        for (final item in merch) {
          final gName = item.hasGroupName() && item.groupName.isNotEmpty
              ? item.groupName
              : otherItems;
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
              : otherItems;
          groupedMerch.putIfAbsent(gName, () => []).add(item);
        }

        final groupKeys = groupedMerch.keys.toList();
        groupKeys.sort((a, b) {
          if (a == otherItems) return 1;
          if (b == otherItems) return -1;
          return _naturalCompare(a, b);
        });
        // Natural sort items within each group
        for (final items in groupedMerch.values) {
          items.sort((a, b) => _naturalCompare(a.name, b.name));
        }

        // Index group metadata by name for the tab shield + info panel (#128).
        final groupsMeta =
            groupsAsync.valueOrNull ?? const <MerchandiseGroup>[];
        final groupByName = <String, MerchandiseGroup>{
          for (final g in groupsMeta) g.groupName: g,
        };

        return DefaultTabController(
          length: groupKeys.length,
          initialIndex: resolveInitialGroupTabIndex(
            groupKeys,
            widget.initialGroupName,
          ),
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
                  hintText: l10n.searchItemsHint,
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
                // How-to guide entry point (#336) — emphasized on first login.
                const HowToTradeIconButton(),
                // Refresh button
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: l10n.refresh,
                  onPressed: () {
                    ref.invalidate(merchProvider(widget.eventId));
                    ref.invalidate(eventGroupsProvider(widget.eventId));
                    if (user != null)
                      ref.invalidate(inventoryProvider(user.id));
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
                  tooltip: l10n.showControls,
                  onSelected: (InventoryDisplayMode result) {
                    ref.read(inventoryDisplayModeProvider.notifier).state =
                        result;
                  },
                  itemBuilder: (BuildContext context) => [
                    PopupMenuItem<InventoryDisplayMode>(
                      value: InventoryDisplayMode.have,
                      child: Text(
                        AppLocalizations.of(context)!.invModeJustHave,
                      ),
                    ),
                    PopupMenuItem<InventoryDisplayMode>(
                      value: InventoryDisplayMode.wantTrade,
                      child: Text(
                        AppLocalizations.of(context)!.invModeWantTrade,
                      ),
                    ),
                    PopupMenuItem<InventoryDisplayMode>(
                      value: InventoryDisplayMode.trade,
                      child: Text(
                        AppLocalizations.of(context)!.invModeJustTrade,
                      ),
                    ),
                    PopupMenuItem<InventoryDisplayMode>(
                      value: InventoryDisplayMode.all,
                      child: Text(AppLocalizations.of(context)!.invModeAll),
                    ),
                  ],
                ),
                PopupMenuButton<ViewMode>(
                  icon: const Icon(Icons.view_agenda),
                  tooltip: l10n.changeViewMode,
                  onSelected: (ViewMode result) {
                    ref.read(viewModeProvider.notifier).state = result;
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<ViewMode>>[
                        PopupMenuItem<ViewMode>(
                          value: ViewMode.detailed,
                          child: Row(
                            children: [
                              const Icon(Icons.view_agenda_outlined, size: 20),
                              const SizedBox(width: 12),
                              Text(AppLocalizations.of(context)!.detailedView),
                            ],
                          ),
                        ),
                        PopupMenuItem<ViewMode>(
                          value: ViewMode.grid,
                          child: Row(
                            children: [
                              const Icon(Icons.grid_view, size: 20),
                              const SizedBox(width: 12),
                              Text(AppLocalizations.of(context)!.gridView),
                            ],
                          ),
                        ),
                        PopupMenuItem<ViewMode>(
                          value: ViewMode.list,
                          child: Row(
                            children: [
                              const Icon(Icons.view_list, size: 20),
                              const SizedBox(width: 12),
                              Text(AppLocalizations.of(context)!.compactList),
                            ],
                          ),
                        ),
                      ],
                ),
                Builder(
                  builder: (context) {
                    // The AppBar is a descendant of DefaultTabController, so this
                    // context resolves the active-tab controller. The State's own
                    // build context is the controller's *parent* and would not
                    // resolve — the export menu previously called
                    // DefaultTabController.of on it, threw at runtime, and the
                    // dialog never opened.
                    final tabCtrl = DefaultTabController.of(context);
                    return PopupMenuButton<String>(
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

                          if (context.mounted &&
                              addedCount > 0 &&
                              failedCount > 0) {
                            // Partial failure: surface both counts so the user
                            // knows not everything was saved (#239).
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  l10n.addedToWantPartial(
                                    addedCount,
                                    failedCount,
                                  ),
                                ),
                              ),
                            );
                          } else if (context.mounted && addedCount > 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  l10n.addedMissingToWant(addedCount),
                                ),
                              ),
                            );
                          } else if (context.mounted && failedCount > 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l10n.couldNotAddToWant)),
                            );
                          } else if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l10n.noMissingItems)),
                            );
                          }
                        } else if (value == 'export') {
                          if (user == null) return;
                          // Export the active tab's group (ADR 0007). The synthetic
                          // "Other items" bucket maps to the empty group name.
                          final index = tabCtrl.index.clamp(
                            0,
                            groupKeys.length - 1,
                          );
                          final groupName = groupKeys[index];
                          final rawGroup = groupName == otherItems
                              ? ''
                              : groupName;
                          // #466: dialog title uses cosmetic display_name;
                          // export still filters inventory by the key.
                          await _showExportInventoryDialog(
                            context,
                            displayGroupName: groupDisplayName(
                              groupName,
                              groupByName,
                            ),
                            rawGroup: rawGroup,
                            user: user,
                          );
                        }
                      },
                      itemBuilder: (BuildContext context) => [
                        PopupMenuItem(
                          value: 'want_missing',
                          child: Text(l10n.wantAllMissing),
                        ),
                        PopupMenuItem(
                          value: 'export',
                          child: Text(l10n.exportInventoryTitle),
                        ),
                      ],
                    );
                  },
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
                          tooltip: l10n.jumpToGroup,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36),
                          onSelected: (idx) => tabCtrl.animateTo(idx),
                          itemBuilder: (_) =>
                              groupKeys.asMap().entries.map((e) {
                                return PopupMenuItem<int>(
                                  value: e.key,
                                  child: Text(
                                    groupDisplayName(e.value, groupByName),
                                  ),
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
                                        ref
                                            .watch(favoriteGroupsProvider)
                                            .valueOrNull ??
                                        [];
                                    final isFav = favGroups.any(
                                      (g) =>
                                          g.eventId == widget.eventId &&
                                          g.groupName == name,
                                    );
                                    // Group edit controls live only at the
                                    // bottom of EventDetailScreen (and the
                                    // info panel) — not on the tab bar (#128).
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          groupDisplayName(name, groupByName),
                                        ),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                          onTap: user == null
                                              ? null
                                              : () async {
                                                  await ref
                                                      .read(
                                                        eventsControllerProvider
                                                            .notifier,
                                                      )
                                                      .toggleFavoriteGroup(
                                                        widget.eventId,
                                                        user.id,
                                                        name,
                                                        !isFav,
                                                      );
                                                  ref.invalidate(
                                                    favoriteGroupsProvider,
                                                  );
                                                },
                                          child: Icon(
                                            isFav
                                                ? Icons.star
                                                : Icons.star_border,
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
            body: Stack(
              children: [
                Column(
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
                                segments: [
                                  ButtonSegment(
                                    value: MerchFilter.all,
                                    label: Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.merchFilterAll,
                                    ),
                                    icon: const Icon(
                                      Icons.inventory_2_outlined,
                                      size: 16,
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: MerchFilter.have,
                                    label: Text(
                                      AppLocalizations.of(context)!.have,
                                    ),
                                    icon: const Icon(
                                      Icons.check_circle_outline,
                                      size: 16,
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: MerchFilter.want,
                                    label: Text(
                                      AppLocalizations.of(context)!.want,
                                    ),
                                    icon: const Icon(
                                      Icons.favorite_border,
                                      size: 16,
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: MerchFilter.trade,
                                    label: Text(
                                      AppLocalizations.of(context)!.trade,
                                    ),
                                    icon: const Icon(
                                      Icons.swap_horiz,
                                      size: 16,
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: MerchFilter.missing,
                                    label: Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.merchFilterMissing,
                                    ),
                                    icon: const Icon(
                                      Icons.help_outline,
                                      size: 16,
                                    ),
                                  ),
                                ],
                                selected: {filterMode},
                                onSelectionChanged:
                                    (Set<MerchFilter> newSelection) {
                                      ref
                                          .read(merchFilterProvider.notifier)
                                          .state = newSelection
                                          .first;
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
                    // Group description panel for the active tab (#128).
                    if (_groupInfoOpen)
                      _buildGroupInfoPanel(
                        context,
                        groupKeys,
                        groupByName,
                        user,
                        otherItems,
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
                                      return Center(
                                        child: Text(
                                          AppLocalizations.of(
                                            context,
                                          )!.noItemsMatchFilter,
                                          style: const TextStyle(
                                            color: Colors.grey,
                                          ),
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
                // Bottom-left controls (#128 / #443): Group info (everyone) +
                // Edit group (creator / event or group canEditGroup, #425/#443)
                // + Manage group members (group-scoped, #443). Event-scoped
                // member management is Home event-card long-press (#483).
                Positioned(
                  left: 16,
                  bottom: 16 + MediaQuery.paddingOf(context).bottom,
                  child: Builder(
                    builder: (context) {
                      final tabCtrl = DefaultTabController.of(context);
                      return AnimatedBuilder(
                        animation: tabCtrl,
                        builder: (context, _) {
                          final index = tabCtrl.index.clamp(
                            0,
                            groupKeys.length - 1,
                          );
                          final activeName = groupKeys[index];
                          final activeMeta = groupByName[activeName];
                          final isSynthetic = activeName == otherItems;
                          final isCreator =
                              user != null &&
                              activeMeta != null &&
                              activeMeta.hasCreatedBy() &&
                              activeMeta.createdBy == user.id;
                          // Group-scoped role for the active tab (#443).
                          final groupRole = !isSynthetic
                              ? ref
                                    .watch(
                                      myGroupRoleProvider((
                                        eventId: widget.eventId,
                                        groupName: activeName,
                                      )),
                                    )
                                    .valueOrNull
                              : null;
                          final canEditActive =
                              user != null &&
                              activeMeta != null &&
                              !isSynthetic &&
                              (isCreator ||
                                  (role?.canEditGroup ?? false) ||
                                  (groupRole?.canEditGroup ?? false));
                          final manageGroupBtn = _buildManageGroupMembersButton(
                            context,
                            activeName,
                            groupRole,
                            isSynthetic: isSynthetic,
                          );

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Icon-only, no label / border / FAB chrome (#128).
                              IconButton(
                                tooltip: l10n.groupInfo,
                                iconSize: 28,
                                onPressed: () {
                                  setState(
                                    () => _groupInfoOpen = !_groupInfoOpen,
                                  );
                                },
                                icon: Icon(
                                  _groupInfoOpen
                                      ? Icons.info
                                      : Icons.info_outline,
                                  color: _groupInfoOpen
                                      ? AppTheme.primaryColor
                                      : null,
                                ),
                              ),
                              if (canEditActive) ...[
                                IconButton(
                                  tooltip: l10n.editGroup,
                                  iconSize: 24,
                                  onPressed: () => _showEditGroupDialog(
                                    context,
                                    activeName,
                                    activeMeta,
                                  ),
                                  icon: const Icon(Icons.edit),
                                ),
                              ],
                              // Group-scoped (#443); depends on active tab.
                              ?manageGroupBtn,
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
            floatingActionButton: _buildAddMerchFab(context),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, stack) =>
          Scaffold(body: Center(child: Text(l10n.errorPrefix(err.toString())))),
    );
  }

  // --- Add Merch FAB (#366) ---
  // Gate the Add Merch button on the caller's effective `merch.create` decision
  // from `GET /events/:id/my-role`, so non-editors no longer see a button that
  // 403s on tap. Returns `null` (no FAB) while the role is loading, on fetch
  // failure, or when the caller cannot create merch — the backend 403 remains
  // the defense-in-depth backstop on the (now-hidden) tap path.
  Widget? _buildAddMerchFab(BuildContext context) {
    final role = ref.watch(myEventRoleProvider(widget.eventId)).valueOrNull;
    if (role == null || !role.canCreateMerch) return null;
    final l10n = AppLocalizations.of(context)!;
    return FloatingActionButton.extended(
      heroTag: 'add_merch_fab',
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddMerchScreen(eventId: widget.eventId),
            fullscreenDialog: true,
          ),
        ).then((_) {
          // New groups may have been created while adding merch.
          ref.invalidate(eventGroupsProvider(widget.eventId));
        });
      },
      label: Text(l10n.addMerch),
      icon: const Icon(Icons.add_photo_alternate),
    );
  }

  /// Bottom-left control for self-service **group** member management (#443).
  /// Visible when the caller can manage group editors and/or transfer group
  /// creator on the active tab. Hidden for the synthetic "Other items" bucket.
  Widget? _buildManageGroupMembersButton(
    BuildContext context,
    String groupName,
    MyGroupRoleResponse? role, {
    required bool isSynthetic,
  }) {
    if (isSynthetic || role == null) return null;
    final canManage = role.canManageEditors || role.canTransferCreator;
    if (!canManage) return null;
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      key: const Key('manage_group_members_button'),
      icon: const Icon(Icons.group),
      tooltip: l10n.manageGroupMembers,
      iconSize: 24,
      onPressed: () => _showManageGroupMembersDialog(context, groupName, role),
    );
  }

  Future<void> _showManageGroupMembersDialog(
    BuildContext context,
    String groupName,
    MyGroupRoleResponse role,
  ) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final l10n = AppLocalizations.of(context)!;
    final events = ref.read(eventsControllerProvider.notifier);

    Future<List<GroupMemberInfo>> loadMembers() =>
        events.listGroupMembers(widget.eventId, groupName, user.id);

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(l10n.manageGroupMembers),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: FutureBuilder<List<GroupMemberInfo>>(
                  future: loadMembers(),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Text(l10n.errorPrefix(snap.error.toString()));
                    }
                    final members = snap.data ?? [];
                    final creatorId = members
                        .where((m) => m.role == 'creator')
                        .map((m) => m.userId)
                        .firstOrNull;

                    Future<void> runAction(
                      Future<void> Function() action,
                      String successLabel, {
                      bool closeOnSuccess = false,
                    }) async {
                      try {
                        await action();
                        ref.invalidate(
                          myGroupRoleProvider((
                            eventId: widget.eventId,
                            groupName: groupName,
                          )),
                        );
                        ref.invalidate(eventGroupsProvider(widget.eventId));
                        if (closeOnSuccess && dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        } else {
                          setDialogState(() {});
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(successLabel)));
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.errorPrefix(e.toString())),
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                            ),
                          );
                        }
                      }
                    }

                    return Column(
                      children: [
                        Expanded(
                          child: members.isEmpty
                              ? Center(child: Text(l10n.noMembers))
                              : ListView.builder(
                                  itemCount: members.length,
                                  itemBuilder: (context, index) {
                                    final m = members[index];
                                    final label =
                                        m.username != null &&
                                            m.username!.isNotEmpty
                                        ? '${m.username} (${m.userId})'
                                        : 'ID ${m.userId}';
                                    final roleLabel = m.role == 'creator'
                                        ? l10n.roleCreator
                                        : m.role == 'editor'
                                        ? l10n.roleEditor
                                        : m.role;
                                    return ListTile(
                                      title: Text(label),
                                      subtitle: Text(roleLabel),
                                      trailing:
                                          role.canManageEditors &&
                                              m.role == 'editor'
                                          ? IconButton(
                                              icon: const Icon(
                                                Icons.remove_circle_outline,
                                                color: Colors.red,
                                              ),
                                              tooltip: l10n.removeEditor,
                                              onPressed: () => runAction(
                                                () => events.revokeGroupEditor(
                                                  widget.eventId,
                                                  groupName,
                                                  m.userId,
                                                  user.id,
                                                ),
                                                l10n.editorRemoved,
                                              ),
                                            )
                                          : null,
                                    );
                                  },
                                ),
                        ),
                        const Divider(),
                        if (role.canManageEditors)
                          ListTile(
                            leading: const Icon(Icons.person_add_alt_1),
                            title: Text(l10n.addEditor),
                            onTap: () async {
                              final selected = await pickUserFromDirectory(
                                dialogContext,
                                ref,
                                title: l10n.pickGroupEditorTitle,
                                excludeUserIds: members
                                    .map((m) => m.userId)
                                    .toSet(),
                              );
                              if (selected == null) return;
                              await runAction(
                                () => events.assignGroupEditor(
                                  widget.eventId,
                                  groupName,
                                  selected.id,
                                  user.id,
                                ),
                                l10n.editorAssigned,
                              );
                            },
                          ),
                        if (role.canTransferCreator)
                          ListTile(
                            leading: const Icon(Icons.swap_horiz),
                            title: Text(l10n.transferCreator),
                            onTap: () async {
                              final selected = await pickUserFromDirectory(
                                dialogContext,
                                ref,
                                title: l10n.pickTransferGroupCreatorTitle,
                                excludeUserIds: {?creatorId},
                              );
                              if (selected == null) return;
                              if (!dialogContext.mounted) return;
                              final confirmed = await showDialog<bool>(
                                context: dialogContext,
                                builder: (ctx) => AlertDialog(
                                  title: Text(
                                    l10n.confirmTransferGroupCreatorTitle,
                                  ),
                                  content: Text(
                                    l10n.confirmTransferGroupCreatorBody(
                                      selected.username,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: Text(l10n.cancel),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: Text(
                                        l10n.confirmTransferCreatorAction,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true) return;
                              await runAction(
                                () => events.transferGroupCreator(
                                  widget.eventId,
                                  groupName,
                                  user.id,
                                  selected.id,
                                ),
                                l10n.groupCreatorTransferred,
                                closeOnSuccess: true,
                              );
                            },
                          ),
                      ],
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(l10n.cancel),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Panel showing the active tab's group name + description (#128).
  /// Tracks the current tab via [DefaultTabController] so switching tabs
  /// updates the panel without closing it.
  Widget _buildGroupInfoPanel(
    BuildContext context,
    List<String> groupKeys,
    Map<String, MerchandiseGroup> groupByName,
    User? user,
    String otherItems,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Builder(
      builder: (context) {
        final tabCtrl = DefaultTabController.of(context);
        return AnimatedBuilder(
          animation: tabCtrl,
          builder: (context, _) {
            final index = tabCtrl.index.clamp(0, groupKeys.length - 1);
            final groupName = groupKeys[index];
            final meta = groupByName[groupName];
            final description =
                meta != null &&
                    meta.hasDescription() &&
                    meta.description.trim().isNotEmpty
                ? meta.description.trim()
                : null;
            final isGroupCreator =
                user != null &&
                meta != null &&
                meta.hasCreatedBy() &&
                meta.createdBy == user.id;
            // Synthetic "Other items" bucket has no formal group row.
            final isSynthetic = groupName == otherItems;

            return Material(
              elevation: 1,
              color: Colors.blueGrey.shade50,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.info_outline, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            groupDisplayName(groupName, groupByName),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isSynthetic
                                ? l10n.noGroupDescription
                                : (description ?? l10n.noGroupDescription),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: description == null
                                      ? Colors.grey[600]
                                      : null,
                                  fontStyle: description == null
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                          ),
                          // Description image below text, width-fit (#404).
                          if (!isSynthetic &&
                              meta != null &&
                              meta.hasPhotoUrl() &&
                              meta.photoUrl.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: double.infinity,
                                child: buildImage(
                                  meta.photoUrl,
                                  width: double.infinity,
                                  fit: BoxFit.fitWidth,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isGroupCreator && !isSynthetic)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: l10n.editGroup,
                        onPressed: () =>
                            _showEditGroupDialog(context, groupName, meta),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: l10n.cancel,
                      onPressed: () => setState(() => _groupInfoOpen = false),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Group-edit dialog: name is read-only; description is editable (#128).
  /// Only called for the group creator (UI gate; backend enforces ownership
  /// / RBAC as well).
  Future<void> _showEditGroupDialog(
    BuildContext context,
    String groupName,
    MerchandiseGroup? meta,
  ) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    await showDialog<void>(
      context: context,
      builder: (context) => _EditGroupDialog(
        eventId: widget.eventId,
        userId: user.id,
        groupName: groupName,
        initialDisplayName: groupDisplayNameFor(groupName, meta),
        initialDescription: meta != null && meta.hasDescription()
            ? meta.description
            : '',
        initialPhotoUrl: meta != null && meta.hasPhotoUrl()
            ? meta.photoUrl
            : null,
      ),
    );
  }

  /// Export-inventory dialog (ADR 0007). Renders the user's own inventory for
  /// [rawGroup] (empty string for the synthetic "Other items" bucket) as
  /// text in the chosen format and copies it to the clipboard. [displayGroupName]
  /// is shown in the title; [rawGroup] is the value used to filter inventory.
  Future<void> _showExportInventoryDialog(
    BuildContext context, {
    required String displayGroupName,
    required String rawGroup,
    required User user,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => ExportInventoryDialog(
        user: user,
        displayGroupName: displayGroupName,
        rawGroup: rawGroup,
      ),
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

    final flags = inventoryDisplayFlags(displayMode);
    final showHave = flags.showHave;
    final showWant = flags.showWant;
    final showTrade = flags.showTrade;

    final isOwner =
        user != null && item.hasCreatorId() && item.creatorId == user.id;
    final isDeleted = item.hasIsDeleted() && item.isDeleted;
    final l10n = AppLocalizations.of(context)!;

    return Opacity(
      opacity: isDeleted ? 0.65 : 1.0,
      child: GestureDetector(
        onLongPress: (isOwner && !isDeleted)
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
                        fit: BoxFit.contain,
                      ),
                    ),
                    if (isDeleted)
                      Positioned(
                        top: 2,
                        left: 2,
                        child: _DeletedBadge(label: l10n.itemDeleted),
                      ),
                    if (isOwner && !isDeleted)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Icon(
                          Icons.edit_note,
                          size: 14,
                          color: Colors.blue[400],
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
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
                        l10n.haveShort,
                        haveQty,
                        AppTheme.haveColor,
                        isDeleted
                            ? null
                            : (q) => _updateInv(ref, user, item.id, 'HAVE', q),
                      ),
                    ),
                  if (showWant)
                    Expanded(
                      child: _buildGridCounter(
                        context,
                        l10n.wantShort,
                        wantQty,
                        AppTheme.wantColor,
                        isDeleted
                            ? null
                            : (q) => _updateInv(ref, user, item.id, 'WANT', q),
                      ),
                    ),
                  if (showTrade)
                    Expanded(
                      child: _buildGridCounter(
                        context,
                        l10n.tradeShort,
                        tradeQty,
                        AppTheme.tradeColor,
                        isDeleted
                            ? null
                            : (q) => _updateInv(ref, user, item.id, 'TRADE', q),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridCounter(
    BuildContext context,
    String label,
    int qty,
    Color color,
    void Function(int)? onUpdate,
  ) {
    final enabled = onUpdate != null;
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
                  onTap: enabled && qty > 0 ? () => onUpdate(qty - 1) : null,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Icon(
                      Icons.remove,
                      size: 12,
                      color: enabled && qty > 0 ? color : Colors.grey,
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
                  onTap: enabled ? () => onUpdate(qty + 1) : null,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Icon(
                      Icons.add,
                      size: 12,
                      color: enabled ? color : Colors.grey,
                    ),
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

    final flags = inventoryDisplayFlags(displayMode);
    final showHave = flags.showHave;
    final showWant = flags.showWant;
    final showTrade = flags.showTrade;

    final isOwner =
        user != null && item.hasCreatorId() && item.creatorId == user.id;
    final isDeleted = item.hasIsDeleted() && item.isDeleted;
    final l10n = AppLocalizations.of(context)!;

    return Opacity(
      opacity: isDeleted ? 0.65 : 1.0,
      child: GestureDetector(
        onLongPress: (isOwner && !isDeleted)
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
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isDeleted) ...[
                      const SizedBox(width: 6),
                      _DeletedBadge(label: l10n.itemDeleted),
                    ],
                  ],
                ),
              ),
              if (isOwner && !isDeleted)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.edit_note,
                    size: 14,
                    color: Colors.blue[400],
                  ),
                ),
              if (showHave)
                _buildCompactCounter(
                  context,
                  l10n.haveShort,
                  haveQty,
                  AppTheme.haveColor,
                  isDeleted
                      ? null
                      : (q) => _updateInv(ref, user, item.id, 'HAVE', q),
                ),
              if (showHave && (showWant || showTrade)) const SizedBox(width: 4),
              if (showWant)
                _buildCompactCounter(
                  context,
                  l10n.wantShort,
                  wantQty,
                  AppTheme.wantColor,
                  isDeleted
                      ? null
                      : (q) => _updateInv(ref, user, item.id, 'WANT', q),
                ),
              if (showWant && showTrade) const SizedBox(width: 4),
              if (showTrade)
                _buildCompactCounter(
                  context,
                  l10n.tradeShort,
                  tradeQty,
                  AppTheme.tradeColor,
                  isDeleted
                      ? null
                      : (q) => _updateInv(ref, user, item.id, 'TRADE', q),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactCounter(
    BuildContext context,
    String label,
    int qty,
    Color color,
    void Function(int)? onUpdate,
  ) {
    final enabled = onUpdate != null;
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
            onTap: enabled && qty > 0 ? () => onUpdate(qty - 1) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.remove,
                size: 12,
                color: enabled && qty > 0 ? color : Colors.grey[400],
              ),
            ),
          ),
          Text(
            '$label$qty',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          InkWell(
            onTap: enabled ? () => onUpdate(qty + 1) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.add,
                size: 12,
                color: enabled ? color : Colors.grey[400],
              ),
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

    final flags = inventoryDisplayFlags(displayMode);
    final showHave = flags.showHave;
    final showWant = flags.showWant;
    final showTrade = flags.showTrade;

    final isOwner =
        user != null && item.hasCreatorId() && item.creatorId == user.id;
    final isDeleted = item.hasIsDeleted() && item.isDeleted;
    final l10n = AppLocalizations.of(context)!;

    return Opacity(
      opacity: isDeleted ? 0.65 : 1.0,
      child: GestureDetector(
        onLongPress: (isOwner && !isDeleted)
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
                      fit: BoxFit.contain,
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
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (isDeleted)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: _DeletedBadge(label: l10n.itemDeleted),
                            ),
                          if (isOwner && !isDeleted)
                            Tooltip(
                              message: l10n.youCreatedThisItem,
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
                                displayLabel: l10n.have,
                                color: AppTheme.haveColor,
                                qty: haveQty,
                                onUpdate: isDeleted
                                    ? null
                                    : (q) => _updateInv(
                                        ref,
                                        user,
                                        item.id,
                                        'HAVE',
                                        q,
                                      ),
                              ),
                            ),
                          if (showHave && (showWant || showTrade))
                            const Spacer(flex: 1),
                          if (showWant)
                            Expanded(
                              flex: 5,
                              child: _buildStepper(
                                label: 'WANT',
                                displayLabel: l10n.want,
                                color: AppTheme.wantColor,
                                qty: wantQty,
                                onUpdate: isDeleted
                                    ? null
                                    : (q) => _updateInv(
                                        ref,
                                        user,
                                        item.id,
                                        'WANT',
                                        q,
                                      ),
                              ),
                            ),
                          if (showWant && showTrade) const Spacer(flex: 1),
                          if (showTrade)
                            Expanded(
                              flex: 5,
                              child: _buildStepper(
                                label: 'TRADE',
                                displayLabel: l10n.trade,
                                color: AppTheme.tradeColor,
                                qty: tradeQty,
                                onUpdate: isDeleted
                                    ? null
                                    : (q) => _updateInv(
                                        ref,
                                        user,
                                        item.id,
                                        'TRADE',
                                        q,
                                      ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(l10n.editItem),
              onTap: () {
                Navigator.pop(ctx);
                _editMerch(context, ref, item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(
                l10n.delete,
                style: const TextStyle(color: Colors.red),
              ),
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

  void _editMerch(BuildContext context, WidgetRef ref, Merchandise item) {
    // The dialog holds its own state (picked image + name) and its own ref,
    // so it is a separate ConsumerStatefulWidget rather than an inline
    // AlertDialog. On save it invalidates `merchProvider` so the card list
    // refreshes with the new name/image.
    showDialog<void>(
      context: context,
      builder: (ctx) => _EditMerchDialog(eventId: widget.eventId, item: item),
    );
  }

  void _confirmDeleteMerch(
    BuildContext context,
    WidgetRef ref,
    Merchandise item,
  ) {
    final user = ref.read(currentUserProvider);
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteItem),
        content: Text(l10n.deleteEventConfirm(item.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (user != null) {
                try {
                  await ref
                      .read(merchControllerProvider.notifier)
                      .deleteMerchByCreator(item.eventId, item.id, user.id);
                  ref.invalidate(merchProvider(widget.eventId));
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  // #266: surface delete failure; keep dialog open.
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.errorPrefix(e.toString())),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                  }
                }
              } else if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  // ... rest of the helpers
  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            l10n.noMerchandiseYet,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.buildInventoryPrompt,
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
    required String displayLabel,
    required Color color,
    required int qty,
    void Function(int)? onUpdate,
  }) {
    final enabled = onUpdate != null;
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
                  onTap: enabled && qty > 0 ? () => onUpdate(qty - 1) : null,
                  child: Container(color: Colors.transparent),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  key: Key('stepper_inc_$label'),
                  behavior: HitTestBehavior.opaque,
                  onTap: enabled ? () => onUpdate(qty + 1) : null,
                  child: Container(color: Colors.transparent),
                ),
              ),
            ],
          ),
          // −/+ hint icons centered on left/right edges.
          // IgnorePointer so taps on the glyphs reach the half-area
          // GestureDetectors below (#408) — same as the center label.
          Positioned(
            left: 2,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Center(
                child: Text(
                  '−',
                  style: TextStyle(
                    fontSize: 9,
                    color: enabled && qty > 0
                        ? color.withValues(alpha: 0.5)
                        : Colors.grey.withValues(alpha: 0.3),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 3,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Center(
                child: Text(
                  '+',
                  style: TextStyle(
                    fontSize: 9,
                    color: enabled
                        ? color.withValues(alpha: 0.5)
                        : Colors.grey.withValues(alpha: 0.3),
                    fontWeight: FontWeight.bold,
                  ),
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
                    displayLabel,
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

/// Group description edit dialog (#128 / #404). Owns its controller so dispose
/// cannot race the route close animation. Image attach/replace uses the same
/// pick + upload flow as merch edit.
class _EditGroupDialog extends ConsumerStatefulWidget {
  final int eventId;
  final int userId;
  final String groupName;
  // #425: editable cosmetic label. Pre-filled with the current display_name,
  // falling back to the (immutable) group_name key so the field never opens
  // empty. Saving writes `display_name`; the key is never sent.
  final String initialDisplayName;
  final String initialDescription;
  final String? initialPhotoUrl;

  const _EditGroupDialog({
    required this.eventId,
    required this.userId,
    required this.groupName,
    required this.initialDisplayName,
    required this.initialDescription,
    this.initialPhotoUrl,
  });

  @override
  ConsumerState<_EditGroupDialog> createState() => _EditGroupDialogState();
}

class _EditGroupDialogState extends ConsumerState<_EditGroupDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  bool _saving = false;

  /// Preview URL (existing remote or base64 of a newly picked image).
  String? _previewUrl;

  /// Raw bytes of a newly picked image (null if no change / no new pick).
  List<int>? _pickedImageBytes;
  String? _pickedImageName;

  /// True when the user explicitly cleared the image.
  bool _removePhoto = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialDisplayName);
    _descCtrl = TextEditingController(text: widget.initialDescription);
    _previewUrl = widget.initialPhotoUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await pickMerchImage(context);
    if (picked == null || !mounted) return;
    setState(() {
      _pickedImageBytes = picked.bytes;
      _pickedImageName = picked.name;
      _previewUrl = picked.previewUrl;
      _removePhoto = false;
    });
  }

  void _clearImage() {
    setState(() {
      _pickedImageBytes = null;
      _pickedImageName = null;
      _previewUrl = null;
      _removePhoto = true;
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    // An empty display name clears it (the backend stores NULL), so the label
    // reverts to the immutable group_name key — that is the UI's "reset to
    // key" path (#425 AC #8). The field opens pre-filled with the current
    // display name (or the key), so clearing is a deliberate action.
    final displayName = _nameCtrl.text.trim();

    setState(() => _saving = true);
    try {
      String? photoUrl;
      var updatePhoto = false;
      if (_pickedImageBytes != null) {
        final uploaded = await ref
            .read(apiClientProvider)
            .uploadImage(_pickedImageBytes!, _pickedImageName ?? 'group.png');
        photoUrl = uploaded;
        updatePhoto = true;
      } else if (_removePhoto) {
        photoUrl = '';
        updatePhoto = true;
      }

      await ref
          .read(groupControllerProvider.notifier)
          .updateGroup(
            eventId: widget.eventId,
            userId: widget.userId,
            groupName: widget.groupName,
            displayName: displayName,
            updateDisplayName: true,
            description: _descCtrl.text.trim(),
            photoUrl: photoUrl,
            updatePhoto: updatePhoto,
          );
      // Info panel reads eventGroupsProvider only — do not invalidate merch:
      // that forces a full-screen loading scaffold and resets the active tab.
      ref.invalidate(eventGroupsProvider(widget.eventId));
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(l10n.groupSaved)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.failedToSaveGroup(e.toString())),
          backgroundColor: errorColor,
        ),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasPreview = _previewUrl != null && _previewUrl!.isNotEmpty;
    return AlertDialog(
      title: Text(l10n.editGroup),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l10n.groupNameLabel,
                helperText: l10n.groupDisplayNameHelper,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: InputDecoration(
                labelText: l10n.groupDescription,
                hintText: l10n.groupDescriptionHint,
              ),
              maxLines: 4,
              enabled: !_saving,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.groupPhoto,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            if (hasPreview)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: double.infinity,
                  child: buildImage(
                    _previewUrl,
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                  ),
                ),
              )
            else
              Container(
                height: 80,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l10n.noGroupPhoto,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickImage,
                  icon: const Icon(Icons.image, size: 18),
                  label: Text(hasPreview ? l10n.changeImage : l10n.chooseImage),
                ),
                if (hasPreview) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _saving ? null : _clearImage,
                    child: Text(
                      l10n.remove,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.save),
        ),
      ],
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

/// Small badge marking soft-deleted merch.
///
/// ADR 0011: event catalog lists are live-only, so this is primarily defensive
/// for stale client state. Inventory rows still carry `is_deleted` (ADR 0008).
class _DeletedBadge extends StatelessWidget {
  final String label;

  const _DeletedBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.grey[700],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Dialog for editing a merch item's name and image (#205).
///
/// The backend `PUT /events/:eventId/merch/:merchId` already accepts `name`
/// and `photo_url`; the previous UI only exposed name editing. This dialog
/// reuses the same image-pick + upload flow as `AddMerchScreen` so a creator
/// can also replace the item's photo. The `photoUrl` is sent only when a new
/// image was picked, so leaving the image untouched does not clobber it.
class _EditMerchDialog extends ConsumerStatefulWidget {
  final int eventId;
  final Merchandise item;

  const _EditMerchDialog({required this.eventId, required this.item});

  @override
  ConsumerState<_EditMerchDialog> createState() => _EditMerchDialogState();
}

class _EditMerchDialogState extends ConsumerState<_EditMerchDialog> {
  late final TextEditingController _nameCtrl;
  // Preview URL for a newly picked image (base64 data URI); null means "show
  // the item's existing photo".
  String? _previewUrl;
  List<int>? _pickedImageBytes;
  String? _pickedImageName;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.item.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await pickMerchImage(context);
    if (picked != null) {
      setState(() {
        _pickedImageBytes = picked.bytes;
        _pickedImageName = picked.name;
        _previewUrl = picked.previewUrl;
      });
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _saving = true);
    try {
      // Only upload + send photoUrl when a new image was picked, so an
      // unchanged image is not overwritten with an empty/stale value.
      String? newPhotoUrl;
      if (_pickedImageBytes != null) {
        newPhotoUrl = await ref
            .read(apiClientProvider)
            .uploadImage(_pickedImageBytes!, _pickedImageName ?? 'image.png');
      }

      await ref
          .read(merchControllerProvider.notifier)
          .updateMerch(
            widget.eventId,
            widget.item.id,
            user.id,
            name: newName,
            photoUrl: newPhotoUrl,
          );
      ref.invalidate(merchProvider(widget.eventId));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // #299: updateMerch rethrows on failure (e.g. a duplicate-name 400).
      // Surface the backend error instead of silently closing the dialog.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.failedToUpdateItem(newName, e.toString())),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentPhotoUrl = widget.item.hasPhotoUrl()
        ? widget.item.photoUrl
        : null;
    return AlertDialog(
      title: Text(l10n.editItem),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 120,
                  height: 120,
                  child: buildImage(
                    _previewUrl ?? currentPhotoUrl,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _saving ? null : _pickImage,
                icon: const Icon(Icons.add_a_photo),
                label: Text(l10n.changeImage),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: InputDecoration(hintText: l10n.editItemNameHint),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
