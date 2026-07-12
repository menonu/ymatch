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
    final user = ref.watch(currentUserProvider);
    final isAdminOrMod =
        user != null && (user.role == 'admin' || user.role == 'moderator');

    if (!isAdminOrMod) {
      return const Scaffold(
        body: Center(
          child: Text('Access denied. Admin or moderator role required.'),
        ),
      );
    }

    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'System'),
              Tab(text: 'Users'),
              Tab(text: 'Events'),
              Tab(text: 'Groups'),
              Tab(text: 'Items'),
              Tab(text: 'Matches'),
              Tab(text: 'Debug'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AdminSystemTab(),
            _AdminUsersTab(),
            _AdminEventsTab(),
            _AdminGroupsTab(),
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

class _AdminUsersTab extends ConsumerWidget {
  const _AdminUsersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(adminUsersProvider);
    final currentUser = ref.watch(currentUserProvider);

    return usersAsync.when(
      data: (users) {
        if (users.isEmpty) {
          return const Center(child: Text('No users found.'));
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(adminUsersProvider);
          },
          child: ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final isBanned = user.hasIsBanned() && user.isBanned;
              final role = user.hasRole() ? user.role : 'user';

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isBanned
                      ? Colors.red[100]
                      : role == 'admin'
                      ? Colors.purple[100]
                      : role == 'moderator'
                      ? Colors.blue[100]
                      : Colors.grey[200],
                  child: Icon(
                    isBanned
                        ? Icons.block
                        : role == 'admin'
                        ? Icons.admin_panel_settings
                        : role == 'moderator'
                        ? Icons.shield
                        : Icons.person,
                    color: isBanned ? Colors.red : null,
                  ),
                ),
                title: Text(
                  user.username,
                  style: TextStyle(
                    decoration: isBanned ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Text(
                  'ID: ${user.id} | Role: $role${isBanned ? ' | BANNED' : ''}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    final adminId = currentUser?.id ?? 0;
                    final admin = ref.read(adminControllerProvider.notifier);
                    switch (value) {
                      case 'ban':
                        final reason = await _showInputDialog(
                          context,
                          'Ban Reason',
                          'Enter reason (optional)',
                        );
                        await admin.banUser(user.id, adminId, reason: reason);
                        ref.invalidate(adminUsersProvider);
                        break;
                      case 'unban':
                        await admin.unbanUser(user.id, adminId);
                        ref.invalidate(adminUsersProvider);
                        break;
                      case 'role_admin':
                        await admin.updateUserRole(user.id, adminId, 'admin');
                        ref.invalidate(adminUsersProvider);
                        break;
                      case 'role_moderator':
                        await admin.updateUserRole(
                          user.id,
                          adminId,
                          'moderator',
                        );
                        ref.invalidate(adminUsersProvider);
                        break;
                      case 'role_user':
                        await admin.updateUserRole(user.id, adminId, 'user');
                        ref.invalidate(adminUsersProvider);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (!isBanned)
                      const PopupMenuItem(
                        value: 'ban',
                        child: Text('🚫 Ban User'),
                      ),
                    if (isBanned)
                      const PopupMenuItem(
                        value: 'unban',
                        child: Text('✅ Unban User'),
                      ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'role_admin',
                      child: Text('👑 Set Admin'),
                    ),
                    const PopupMenuItem(
                      value: 'role_moderator',
                      child: Text('🛡️ Set Moderator'),
                    ),
                    const PopupMenuItem(
                      value: 'role_user',
                      child: Text('👤 Set User'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }

  Future<String?> _showInputDialog(
    BuildContext context,
    String title,
    String hint,
  ) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
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
            final isDraft = event.hasStatus() && event.status == 'draft';
            return ListTile(
              leading: Icon(Icons.event, color: isDraft ? Colors.orange : null),
              title: Row(
                children: [
                  Expanded(child: Text(event.name)),
                  if (isDraft)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'DRAFT',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange[800],
                        ),
                      ),
                    ),
                ],
              ),
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
                      final user = ref.read(currentUserProvider);
                      final userId = user?.id ?? 0;
                      await client.delete(
                        '/api/v1/admin/events/${event.id}?user_id=$userId',
                      );
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

class _AdminGroupsTab extends ConsumerWidget {
  const _AdminGroupsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(adminGroupsProvider);
    return groupsAsync.when(
      data: (groups) {
        if (groups.isEmpty) {
          return const Center(child: Text('No groups found.'));
        }
        return ListView.builder(
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            return ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(group.groupName),
              subtitle: Text(
                '${group.eventName} (Event ID: ${group.eventId}) | ${group.itemCount} live items',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: 'Remove group',
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Remove item group?'),
                      content: Text(
                        'Remove “${group.groupName}” from “${group.eventName}”? '
                        'All of its items will be hidden, and its matches and favourites will be removed. This cannot be undone.',
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
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  try {
                    final userId = ref.read(currentUserProvider)?.id ?? 0;
                    final encodedName = Uri.encodeComponent(group.groupName);
                    await ref
                        .read(apiClientProvider)
                        .delete(
                          '/api/v1/admin/events/${group.eventId}/groups/$encodedName?user_id=$userId',
                        );
                    ref.invalidate(adminGroupsProvider);
                    ref.invalidate(adminMerchProvider);
                    ref.invalidate(adminMatchesProvider);
                    ref.invalidate(eventsProvider);
                    ref.invalidate(favoriteGroupsProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Item group removed')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to remove group: $e')),
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
      error: (error, _) => Center(child: Text('Error: $error')),
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
                      fit: BoxFit.contain,
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
                      final user = ref.read(currentUserProvider);
                      final userId = user?.id ?? 0;
                      await client.delete(
                        '/api/v1/admin/merch/${item.id}?user_id=$userId',
                      );
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
                          final user = ref.read(currentUserProvider);
                          final userId = user?.id ?? 0;
                          await client.delete(
                            '/api/v1/admin/matches/${match.id}?user_id=$userId',
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
