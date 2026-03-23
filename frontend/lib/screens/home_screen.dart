import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../models/models.dart';

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
            hintText: 'Search events, groups...',
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
          if (searchQuery.isEmpty) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(eventsProvider),
            ),
            PopupMenuButton<EventSort>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort Events',
              onSelected: (EventSort result) {
                ref.read(eventSortProvider.notifier).state = result;
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<EventSort>>[
                    const PopupMenuItem<EventSort>(
                      value: EventSort.recent,
                      child: Text('Newest First'),
                    ),
                    const PopupMenuItem<EventSort>(
                      value: EventSort.popular,
                      child: Text('Most Popular'),
                    ),
                    const PopupMenuItem<EventSort>(
                      value: EventSort.alphabetical,
                      child: Text('Alphabetical'),
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
              label: const Text('New Event'),
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
                              'Fav: ${event.name}',
                              event.id,
                            ),
                          );
                        }),
                        ...favGroups.map((group) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _buildShortcutChip(
                              context,
                              Icons.star,
                              '${group.hasEventName() ? group.eventName : 'Group'}: ${group.groupName}',
                              group.eventId,
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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<EventFilter>(
                segments: const [
                  ButtonSegment(
                    value: EventFilter.all,
                    label: Text('All Events'),
                  ),
                  ButtonSegment(
                    value: EventFilter.favorite,
                    label: Text('Favorites'),
                  ),
                  ButtonSegment(
                    value: EventFilter.joined,
                    label: Text('My Items'),
                  ),
                ],
                selected: {filterMode},
                onSelectionChanged: (Set<EventFilter> newSelection) {
                  ref.read(eventFilterProvider.notifier).state =
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
                return const Center(
                  child: Text(
                    'No events match this filter.',
                    style: TextStyle(color: Colors.grey),
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
                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.go('/event/${event.id}'),
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
                                  if (event.hasStatus() &&
                                      event.status == 'draft')
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange[100],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text('DRAFT',
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orange[800])),
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
                                        '${event.hasActiveParticipants() ? event.activeParticipants : 0} traders',
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
                                        '${event.hasUniqueViews() ? event.uniqueViews : 0} views',
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
                                        _formatDate(event.createdAt),
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
            error: (err, stack) => Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }

  Widget _buildShortcutChip(
    BuildContext context,
    IconData icon,
    String label,
    int eventId,
  ) {
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
        // Navigate to the event. In a real implementation, we would also need to pass the group name
        // to automatically switch the tab, or the EventDetailScreen would read the desired group from GoRouter state.
        context.go('/event/$eventId');
      },
    );
  }

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return 'Unknown date';
    try {
      final date = DateTime.parse(isoDate).toLocal();
      return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'Invalid date';
    }
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No events found',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Create an event to start trading.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Create Event'),
            onPressed: () => _showAddEventDialog(context, ref),
          ),
        ],
      ),
    );
  }

  void _showAddEventDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Event'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Event Name',
            hintText: 'e.g., Summer Comic Market 2025',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final user = ref.read(currentUserProvider);
              if (name.isNotEmpty && user != null) {
                await ref
                    .read(eventsControllerProvider.notifier)
                    .addEvent(name, user.id);
                ref.invalidate(eventsProvider); // Refresh list
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
