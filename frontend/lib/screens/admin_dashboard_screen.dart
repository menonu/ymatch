import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/models.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Events'),
              Tab(text: 'Items'),
              Tab(text: 'Matches'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AdminEventsTab(),
            _AdminItemsTab(),
            _AdminMatchesTab(),
          ],
        ),
      ),
    );
  }
}

class _AdminEventsTab extends ConsumerWidget {
  const _AdminEventsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsProvider);

    return eventsAsync.when(
      data: (events) {
        if (events.isEmpty) {
          return const Center(child: Text('No events found.'));
        }
        return ListView.builder(
          itemCount: events.length,
          itemBuilder: (context, index) {
            final event = events[index];
            return ListTile(
              leading: const Icon(Icons.event),
              title: Text(event.name),
              subtitle: Text('ID: ${event.id} | Creator: ${event.hasCreatorId() ? event.creatorId : 'Unknown'} | Views: ${event.hasUniqueViews() ? event.uniqueViews : 0}'),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}

class _AdminItemsTab extends ConsumerWidget {
  const _AdminItemsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(adminMerchProvider);

    return itemsAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return const Center(child: Text('No items found.'));
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: item.hasPhotoUrl() && item.photoUrl.isNotEmpty
                  ? Image.network(item.photoUrl, width: 50, height: 50, fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_not_supported))
                  : const Icon(Icons.image),
              title: Text(item.name),
              subtitle: Text('ID: ${item.id} | Event ID: ${item.eventId} | Group: ${item.hasGroupName() ? item.groupName : 'None'}'),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}

class _AdminMatchesTab extends ConsumerWidget {
  const _AdminMatchesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(adminMatchesProvider);

    return matchesAsync.when(
      data: (matches) {
        if (matches.isEmpty) {
          return const Center(child: Text('No matches found.'));
        }
        return ListView.builder(
          itemCount: matches.length,
          itemBuilder: (context, index) {
            final match = matches[index];
            return ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text('Match ID: ${match.id}'),
              subtitle: Text('User 1: ${match.user1Id} | User 2: ${match.user2Id} | Status: ${match.status}'),
              trailing: Text(match.hasCreatedAt() ? match.createdAt.split('T').first : ''),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}
