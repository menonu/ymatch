import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../utils/group_display.dart';
import '../widgets/export_inventory_dialog.dart';
import '../widgets/how_to_trade.dart';
import '../widgets/manage_event_members_dialog.dart';
import 'add_merch_screen.dart';
import 'event_detail/edit_group_dialog.dart';
import 'event_detail/group_info_panel.dart';
import 'event_detail/inventory_item_tiles.dart';
import 'event_detail/merch_filters.dart';

export 'event_detail/merch_filters.dart';

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
    final viewMode = ref.watch(viewModeProvider(widget.eventId));
    final filterMode = ref.watch(merchFilterProvider(widget.eventId));
    final displayMode = ref.watch(inventoryDisplayModeProvider(widget.eventId));
    final searchQuery = ref.watch(itemSearchQueryProvider(widget.eventId));
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
          return naturalCompare(a, b);
        });
        // Natural sort items within each group
        for (final items in groupedMerch.values) {
          items.sort((a, b) => naturalCompare(a.name, b.name));
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
                          ref
                                  .read(
                                    itemSearchQueryProvider(
                                      widget.eventId,
                                    ).notifier,
                                  )
                                  .state =
                              '';
                        },
                      ),
                  ],
                  onChanged: (value) {
                    ref
                            .read(
                              itemSearchQueryProvider(widget.eventId).notifier,
                            )
                            .state =
                        value;
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
                    if (user != null) {
                      ref.invalidate(inventoryProvider(user.id));
                    }
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
                    ref
                            .read(
                              inventoryDisplayModeProvider(
                                widget.eventId,
                              ).notifier,
                            )
                            .state =
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
                    ref.read(viewModeProvider(widget.eventId).notifier).state =
                        result;
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
                                              .read(
                                                merchFilterProvider(
                                                  widget.eventId,
                                                ).notifier,
                                              )
                                              .state =
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
                    // Group description panel for the active tab (#128).
                    if (_groupInfoOpen)
                      GroupInfoPanel(
                        groupKeys: groupKeys,
                        groupByName: groupByName,
                        user: user,
                        otherItems: otherItems,
                        onClose: () => setState(() => _groupInfoOpen = false),
                        onEditGroup: (name, meta) =>
                            _showEditGroupDialog(context, name, meta),
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
                                            buildGridInventoryItem(
                                              context,
                                              ref,
                                              widget.eventId,
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
                                            buildCompactInventoryItem(
                                              context,
                                              ref,
                                              widget.eventId,
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
                                          return buildDetailedInventoryItem(
                                            context,
                                            ref,
                                            widget.eventId,
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
      onPressed: () => showManageGroupMembersDialog(
        context,
        ref,
        eventId: widget.eventId,
        groupName: groupName,
        role: role,
      ),
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
      builder: (context) => EditGroupDialog(
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
}
