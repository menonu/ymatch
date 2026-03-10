import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'System'),
              Tab(text: 'Events'),
              Tab(text: 'Items'),
              Tab(text: 'Matches'),
              Tab(text: 'Debug'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AdminSystemTab(),
            _AdminEventsTab(),
            _AdminItemsTab(),
            _AdminMatchesTab(),
            _AdminDebugTab(),
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
        final totalMemMB = (res['total_memory_bytes'] / (1024 * 1024))
            .toStringAsFixed(0);
        final usedMemMB = (res['used_memory_bytes'] / (1024 * 1024))
            .toStringAsFixed(0);
        final cpuUsage = (res['cpu_usage_percent'] as num).toStringAsFixed(1);
        final uptimeStr = Duration(
          seconds: res['uptime_seconds'],
        ).toString().split('.').first;

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
                  subtitle: Text(
                    status['backend_version'],
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
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
              subtitle: Text(
                'ID: ${event.id} | Creator: ${event.hasCreatorId() ? event.creatorId : 'Unknown'} | Views: ${event.hasUniqueViews() ? event.uniqueViews : 0}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete Event?'),
                      content: const Text(
                        'Are you sure you want to delete this event? This will cascade and delete all related merchandise and inventory.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    try {
                      final client = ref.read(apiClientProvider);
                      await client.delete('/api/v1/admin/events/${event.id}');
                      ref.invalidate(eventsProvider);
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Event deleted')),
                        );
                    } catch (e) {
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to delete: $e')),
                        );
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
                  ? Image.network(
                      item.photoUrl,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.image_not_supported),
                    )
                  : const Icon(Icons.image),
              title: Text(item.name),
              subtitle: Text(
                'ID: ${item.id} | Event ID: ${item.eventId} | Group: ${item.hasGroupName() ? item.groupName : 'None'}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete Merchandise?'),
                      content: const Text(
                        'Are you sure you want to delete this item?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    try {
                      final client = ref.read(apiClientProvider);
                      await client.delete('/api/v1/admin/merch/${item.id}');
                      ref.invalidate(adminMerchProvider);
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Item deleted')),
                        );
                    } catch (e) {
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to delete: $e')),
                        );
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
              subtitle: Text(
                'User 1: ${match.user1Id} | User 2: ${match.user2Id} | Status: ${match.status}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    match.hasCreatedAt()
                        ? match.createdAt.split('T').first
                        : '',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete Match?'),
                          content: const Text(
                            'Are you sure you want to delete this match record?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        try {
                          final client = ref.read(apiClientProvider);
                          await client.delete(
                            '/api/v1/admin/matches/${match.id}',
                          );
                          ref.invalidate(adminMatchesProvider);
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Match deleted')),
                            );
                        } catch (e) {
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to delete: $e')),
                            );
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

class _AdminDebugTab extends ConsumerWidget {
  const _AdminDebugTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: EdgeInsets.zero,
            color: Colors.amber[50], // Subtle warning/debug color
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bug_report, color: Colors.amber[900]),
                      const SizedBox(width: 8),
                      Text(
                        'Developer / Debug Tools',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber[900],
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildVersionInfo(context, ref),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_to_photos),
                      label: const Text(
                        'Generate Test Event (50 items in 5 tabs)',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber[800],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () async {
                        if (user == null) return;

                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Generate Data?'),
                            content: const Text(
                              'This will create a dummy event with 50 items spread across 5 group tabs. Proceed?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Generate'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Generating data...'),
                              ),
                            );
                          }
                          await ref
                              .read(eventsControllerProvider.notifier)
                              .generateDebugData(user.id);
                          ref.invalidate(eventsProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Test data generated successfully!',
                                ),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open New Guest Session in Browser'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () {
                        final newUuid = const Uuid().v4();
                        final currentUrl = Uri.base.origin;
                        final newUrl = Uri.parse(
                          '$currentUrl/#/?dev_user=$newUuid',
                        );
                        launchUrl(newUrl, webOnlyWindowName: '_blank');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            color: Colors.red[50], // Danger Zone color
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red[900]),
                      const SizedBox(width: 8),
                      Text(
                        'Danger Zone',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.red[900],
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Reset My Data (Inventory & Matches)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () async {
                        if (user == null) return;

                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Reset My Data?'),
                            content: const Text(
                              'This will permanently delete ALL your Inventory (HAVE/WANT) records, Trade Matches, and Messages. It will NOT delete events or items you created. Proceed?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text('Reset Data'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Resetting data...'),
                              ),
                            );
                          }
                          try {
                            final client = ref.read(apiClientProvider);
                            await client.post('/api/v1/debug/reset_me', {
                              'user_id': user.id,
                            });
                            // We need to invalidate things to reflect the UI
                            ref.invalidate(inventoryProvider);
                            // We cannot invalidate matchesProvider directly as it is not imported here. It is fine if it reloads when user visits trade list screen.
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Data reset successfully!'),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to reset data: $e'),
                                ),
                              );
                            }
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.local_fire_department),
                      label: const Text('Nuke & Seed DB'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[900],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('NUKE & SEED DATABASE?'),
                            content: const Text(
                              'WARNING: This will instantly WIPE OUT ALL Events, Items, Users, and Matches in the database, and then re-seed a Demo Event. This action cannot be undone. Proceed?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red[900],
                                ),
                                child: const Text('NUKE IT'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Nuking and Seeding database...'),
                              ),
                            );
                          }
                          try {
                            final client = ref.read(apiClientProvider);
                            await client.post('/api/v1/debug/nuke_seed', {});
                            ref.invalidate(eventsProvider);
                            ref.invalidate(adminMerchProvider);
                            ref.invalidate(adminMatchesProvider);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Database Nuked and Seeded successfully! Reloading...',
                                  ),
                                ),
                              );
                              // A hard reload or navigation might be necessary, but invalidate covers most
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to Nuke & Seed: $e'),
                                ),
                              );
                            }
                          }
                        }
                      },
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

  Widget _buildVersionInfo(BuildContext context, WidgetRef ref) {
    final backendStatus = ref.watch(backendSystemStatusProvider);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Versions',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.amber[900],
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          backendStatus.when(
            data: (status) => SelectableText(
              'Backend (Git Hash): ${status['backend_version']}',
              style: TextStyle(
                color: Colors.amber[900],
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
            loading: () => const Text('Backend: Loading...'),
            error: (_, __) => const Text('Backend: Error fetching version'),
          ),
        ],
      ),
    );
  }
}
