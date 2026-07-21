import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/group_display.dart';
import '../widgets/how_to_trade.dart';
import '../widgets/manage_event_members_dialog.dart';

enum EventSort { recent, popular, alphabetical }

final eventSortProvider = StateProvider<EventSort>((ref) => EventSort.recent);

enum EventFilter { all, favorite, joined }

final eventFilterProvider = StateProvider<EventFilter>(
  (ref) => EventFilter.all,
);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsProvider);
    final sortMode = ref.watch(eventSortProvider);
    final filterMode = ref.watch(eventFilterProvider);
    final user = ref.watch(currentUserProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
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
            hintText: l10n.searchEventsHint,
            leading: const Icon(Icons.search, size: 20),
            trailing: [
              if (searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    ref.read(searchQueryProvider.notifier).state = '';
                  },
                ),
            ],
            onChanged: (value) {
              ref.read(searchQueryProvider.notifier).state = value;
            },
          ),
        ),
        actions: [
          const HowToTradeIconButton(),
          if (searchQuery.isEmpty) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.refresh,
              onPressed: () => ref.invalidate(eventsProvider),
            ),
            PopupMenuButton<EventSort>(
              icon: const Icon(Icons.sort),
              tooltip: l10n.sortEvents,
              onSelected: (EventSort result) {
                ref.read(eventSortProvider.notifier).state = result;
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<EventSort>>[
                    PopupMenuItem<EventSort>(
                      value: EventSort.recent,
                      child: Text(l10n.sortNewestFirst),
                    ),
                    PopupMenuItem<EventSort>(
                      value: EventSort.popular,
                      child: Text(l10n.sortMostPopular),
                    ),
                    PopupMenuItem<EventSort>(
                      value: EventSort.alphabetical,
                      child: Text(l10n.sortAlphabetical),
                    ),
                  ],
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildNormalContent(
              context,
              ref,
              eventsAsync,
              sortMode,
              filterMode,
              user,
              searchQuery,
            ),
          ),
        ],
      ),
      floatingActionButton: searchQuery.isEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showAddEventDialog(context, ref),
              icon: const Icon(Icons.add),
              label: Text(l10n.newEvent),
            )
          : null,
    );
  }

  Widget _buildNormalContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Event>> eventsAsync,
    EventSort sortMode,
    EventFilter filterMode,
    User? user,
    String searchQuery,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (searchQuery.isEmpty)
          Consumer(
            builder: (context, ref, _) {
              final eventsAsync = ref.watch(eventsProvider);
              final groupsAsync = ref.watch(favoriteGroupsProvider);

              final favEvents =
                  eventsAsync.valueOrNull
                      ?.where((e) => e.hasIsFavorite() && e.isFavorite)
                      .take(2)
                      .toList() ??
                  [];
              final favGroups = groupsAsync.valueOrNull?.take(4).toList() ?? [];

              if (favEvents.isEmpty && favGroups.isEmpty) {
                return const SizedBox.shrink();
              }

              return Column(
                children: [
                  Container(
                    height: 60,
                    color: Colors.white,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      children: [
                        ...favEvents.map((event) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _buildShortcutChip(
                              context,
                              Icons.event,
                              AppLocalizations.of(
                                context,
                              )!.favPrefix(event.name),
                              event.id,
                            ),
                          );
                        }),
                        ...favGroups.map((group) {
                          final l10n = AppLocalizations.of(context)!;
                          // #466: chip label uses display_name when the API
                          // returns it; navigation still uses group_name key.
                          final label = groupLabel(
                            group.groupName,
                            group.hasDisplayName() ? group.displayName : null,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _buildShortcutChip(
                              context,
                              Icons.star,
                              l10n.groupChipLabel(
                                group.hasEventName()
                                    ? group.eventName
                                    : l10n.groupFallback,
                                label,
                              ),
                              group.eventId,
                              groupName: group.groupName,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFEEEEEE)),
                ],
              );
            },
          ),
        if (searchQuery.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: SegmentedButton<EventFilter>(
              // `expandedInsets` makes the button expand to fill its parent's
              // width and distributes it equally across segments, so the bar
              // fits the screen on one row instead of scrolling horizontally
              // (issue #415). The outer Container provides the 16px gutters.
              expandedInsets: EdgeInsets.zero,
              // Suppress the default selected check icon so each segment's
              // width is identical in its selected and unselected states
              // (issue #324). Selection is still conveyed by the segmented
              // button's selected background color.
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: EventFilter.all,
                  label: Text(
                    AppLocalizations.of(context)!.filterAllEvents,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                ButtonSegment(
                  value: EventFilter.favorite,
                  label: Text(
                    AppLocalizations.of(context)!.filterFavorites,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                ButtonSegment(
                  value: EventFilter.joined,
                  label: Text(
                    AppLocalizations.of(context)!.filterMyItems,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
              selected: {filterMode},
              onSelectionChanged: (Set<EventFilter> newSelection) {
                ref.read(eventFilterProvider.notifier).state =
                    newSelection.first;
              },
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                // Trim segment gutters so the longest localized label
                // (Japanese "すべてのイベント") stays on one line at the
                // narrowest supported width (issue #415).
                padding: const EdgeInsets.symmetric(horizontal: 6),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        Expanded(
          child: eventsAsync.when(
            data: (originalEvents) {
              if (originalEvents.isEmpty) return _buildEmptyState(context, ref);

              var events = originalEvents.where((e) {
                if (searchQuery.isNotEmpty &&
                    !e.name.toLowerCase().contains(searchQuery.toLowerCase())) {
                  return false;
                }
                if (filterMode == EventFilter.favorite) {
                  return e.hasIsFavorite() && e.isFavorite;
                }
                if (filterMode == EventFilter.joined) {
                  return e.hasIsJoined() && e.isJoined;
                }
                return true;
              }).toList();

              if (events.isEmpty) {
                return Center(
                  child: Text(
                    AppLocalizations.of(context)!.noEventsMatchFilter,
                    style: const TextStyle(color: Colors.grey),
                  ),
                );
              }

              events.sort((a, b) {
                final aFav = a.hasIsFavorite() && a.isFavorite;
                final bFav = b.hasIsFavorite() && b.isFavorite;
                if (aFav && !bFav) return -1;
                if (!aFav && bFav) return 1;

                switch (sortMode) {
                  case EventSort.popular:
                    final aPop = a.hasActiveParticipants()
                        ? a.activeParticipants
                        : 0;
                    final bPop = b.hasActiveParticipants()
                        ? b.activeParticipants
                        : 0;
                    return bPop.compareTo(aPop);
                  case EventSort.alphabetical:
                    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                  case EventSort.recent:
                    return b.id.compareTo(a.id);
                }
              });

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  final isOwner =
                      user != null &&
                      event.hasCreatorId() &&
                      event.creatorId == user.id;
                  // #483: long-press resolves my-role lazily (no N× watch per
                  // card). Owner always gets rename/delete; manage tiles only
                  // when role allows. Viewers no-op after the await.
                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: Key('event_card_${event.id}'),
                      onTap: () => context.go('/event/${event.id}'),
                      onLongPress: user != null
                          ? () => _showEventActions(
                              context,
                              ref,
                              event,
                              isOwner: isOwner,
                            )
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.confirmation_number_outlined,
                                color: Theme.of(context).colorScheme.primary,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    event.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  if (isOwner)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Icon(
                                        Icons.edit_note,
                                        size: 16,
                                        color: Colors.blue[400],
                                      ),
                                    ),
                                  if (event.hasStatus() &&
                                      event.status == 'draft')
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange[100],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.draftBadge,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange[800],
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.people_outline,
                                        size: 14,
                                        color: Colors.grey[600],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.tradersCount(
                                          event.hasActiveParticipants()
                                              ? event.activeParticipants
                                              : 0,
                                        ),
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Icon(
                                        Icons.visibility_outlined,
                                        size: 14,
                                        color: Colors.grey[600],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.viewsCount(
                                          event.hasUniqueViews()
                                              ? event.uniqueViews
                                              : 0,
                                        ),
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today_outlined,
                                        size: 14,
                                        color: Colors.grey[600],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatDate(context, event.createdAt),
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                event.hasIsFavorite() && event.isFavorite
                                    ? Icons.star
                                    : Icons.star_border,
                                color: event.hasIsFavorite() && event.isFavorite
                                    ? Colors.amber
                                    : Colors.grey,
                              ),
                              onPressed: () async {
                                if (user != null) {
                                  final newStatus =
                                      !(event.hasIsFavorite() &&
                                          event.isFavorite);
                                  await ref
                                      .read(eventsControllerProvider.notifier)
                                      .toggleFavorite(
                                        event.id,
                                        user.id,
                                        newStatus,
                                      );
                                  ref.invalidate(eventsProvider);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(
              child: Text(
                AppLocalizations.of(context)!.errorPrefix(err.toString()),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShortcutChip(
    BuildContext context,
    IconData icon,
    String label,
    int eventId, {
    String? groupName,
  }) {
    return ActionChip(
      avatar: Icon(
        icon,
        size: 16,
        color: Theme.of(context).colorScheme.primary,
      ),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      backgroundColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.05),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onPressed: () {
        // Favorite-group chips pass ?group= so EventDetailScreen opens that tab (#406).
        if (groupName != null && groupName.isNotEmpty) {
          context.go(
            Uri(
              path: '/event/$eventId',
              queryParameters: {'group': groupName},
            ).toString(),
          );
        } else {
          context.go('/event/$eventId');
        }
      },
    );
  }

  String _formatDate(BuildContext context, String isoDate) {
    final l10n = AppLocalizations.of(context)!;
    if (isoDate.isEmpty) return l10n.unknownDate;
    try {
      final date = DateTime.parse(isoDate).toLocal();
      return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return l10n.invalidDate;
    }
  }

  Future<void> _showEventActions(
    BuildContext context,
    WidgetRef ref,
    Event event, {
    required bool isOwner,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    // Resolve role on demand so Home does not N× subscribe to my-role (#483).
    final role = await ref.read(myEventRoleProvider(event.id).future);
    final canManageMembers =
        role != null && (role.canManageEditors || role.canTransferCreator);
    if (!isOwner && !canManageMembers) return;
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOwner) ...[
              ListTile(
                leading: const Icon(Icons.edit),
                title: Text(l10n.editName),
                onTap: () {
                  Navigator.pop(ctx);
                  _editEventName(context, ref, event);
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
                  _confirmDeleteEvent(context, ref, event);
                },
              ),
            ],
            // #483: event-scope member management (same dialog as #442).
            if (canManageMembers && role != null)
              ListTile(
                key: const Key('manage_members_action'),
                leading: const Icon(Icons.manage_accounts),
                title: Text(l10n.manageMembers),
                onTap: () {
                  Navigator.pop(ctx);
                  showManageEventMembersDialog(
                    context,
                    ref,
                    eventId: event.id,
                    role: role,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _editEventName(BuildContext context, WidgetRef ref, Event event) {
    final ctrl = TextEditingController(text: event.name);
    final user = ref.read(currentUserProvider);
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.editEventName),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.eventNameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isNotEmpty && user != null) {
                try {
                  await ref
                      .read(eventsControllerProvider.notifier)
                      .updateEvent(event.id, user.id, newName);
                  ref.invalidate(eventsProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  // #266: surface rename failure; keep dialog open.
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
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteEvent(BuildContext context, WidgetRef ref, Event event) {
    final user = ref.read(currentUserProvider);
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteEvent),
        content: Text(l10n.deleteEventConfirm(event.name)),
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
                      .read(eventsControllerProvider.notifier)
                      .deleteEventByCreator(event.id, user.id);
                  ref.invalidate(eventsProvider);
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

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            l10n.noEventsFound,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.createEventPrompt,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: Text(l10n.createEvent),
            onPressed: () => _showAddEventDialog(context, ref),
          ),
        ],
      ),
    );
  }

  void _showAddEventDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final eventsAsync = ref.read(eventsProvider);
    final eventCount = eventsAsync.valueOrNull?.length ?? 0;
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.newEvent),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: l10n.eventNameLabel,
            hintText: l10n.newEventNameHint(eventCount + 1),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final user = ref.read(currentUserProvider);
              if (name.isNotEmpty && user != null) {
                try {
                  await ref
                      .read(eventsControllerProvider.notifier)
                      .addEvent(name, user.id);
                  ref.invalidate(eventsProvider); // Refresh list
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  // #266: surface create failure; keep dialog open.
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.errorPrefix(e.toString())),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                  }
                }
              }
            },
            child: Text(l10n.create),
          ),
        ],
      ),
    );
  }
}
