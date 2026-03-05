import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'System'),
              Tab(text: 'Events'),
              Tab(text: 'Items'),
              Tab(text: 'Matches'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AdminSystemTab(),
            _AdminEventsTab(),
            _AdminItemsTab(),
            _AdminMatchesTab(),
          ],
        ),
      ),
    );
  }
}

class _AdminSystemTab extends ConsumerWidget {
  const _AdminSystemTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(backendSystemStatusProvider);

    return statusAsync.when(
      data: (status) {
        if (status['resources'] == null) {
          return const Center(child: Text('Failed to load system resources.'));
        }
        
        final res = status['resources'];
        final totalMemMB = (res['total_memory_bytes'] / (1024 * 1024)).toStringAsFixed(0);
        final usedMemMB = (res['used_memory_bytes'] / (1024 * 1024)).toStringAsFixed(0);
        final cpuUsage = (res['cpu_usage_percent'] as num).toStringAsFixed(1);
        final uptimeStr = Duration(seconds: res['uptime_seconds']).toString().split('.').first;

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(backendSystemStatusProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.commit),
                  title: const Text('Backend Revision'),
                  subtitle: Text(status['backend_version'], style: const TextStyle(fontFamily: 'monospace')),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.memory),
                      title: const Text('Memory Usage'),
                      subtitle: Text('$usedMemMB MB / $totalMemMB MB'),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.speed),
                      title: const Text('CPU Usage'),
                      subtitle: Text('$cpuUsage%'),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.timer),
                      title: const Text('Uptime'),
                      subtitle: Text(uptimeStr),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.computer),
                      title: const Text('Operating System'),
                      subtitle: Text('${res['os_name']} ${res['os_version']}'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
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
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete Event?'),
                      content: const Text('Are you sure you want to delete this event? This will cascade and delete all related merchandise and inventory.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    try {
                      final client = ref.read(apiClientProvider);
                      await client.delete('/api/v1/admin/events/${event.id}');
                      ref.invalidate(eventsProvider);
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event deleted')));
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
                    }
                  }
                },
              ),
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
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete Merchandise?'),
                      content: const Text('Are you sure you want to delete this item?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    try {
                      final client = ref.read(apiClientProvider);
                      await client.delete('/api/v1/admin/merch/${item.id}');
                      ref.invalidate(adminMerchProvider);
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item deleted')));
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
                    }
                  }
                },
              ),
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(match.hasCreatedAt() ? match.createdAt.split('T').first : ''),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete Match?'),
                          content: const Text('Are you sure you want to delete this match record?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        try {
                          final client = ref.read(apiClientProvider);
                          await client.delete('/api/v1/admin/matches/${match.id}');
                          ref.invalidate(adminMatchesProvider);
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Match deleted')));
                        } catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}
