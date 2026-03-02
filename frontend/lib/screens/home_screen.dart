import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Events'),
      ),
      body: eventsAsync.when(
        data: (events) => events.isEmpty
            ? _buildEmptyState(context, ref)
            : ListView.builder(
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
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
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
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.people_outline, size: 14, color: Colors.grey[600]),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${event.hasActiveParticipants() ? event.activeParticipants : 0} traders',
                                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                                      ),
                                      const SizedBox(width: 12),
                                      Icon(Icons.visibility_outlined, size: 14, color: Colors.grey[600]),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${event.hasUniqueViews() ? event.uniqueViews : 0} views',
                                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey[600]),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatDate(event.createdAt),
                                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                event.hasIsFavorite() && event.isFavorite ? Icons.star : Icons.star_border,
                                color: event.hasIsFavorite() && event.isFavorite ? Colors.amber : Colors.grey,
                              ),
                              onPressed: () async {
                                final user = ref.read(currentUserProvider);
                                if (user != null) {
                                  final newStatus = !(event.hasIsFavorite() && event.isFavorite);
                                  await ref.read(eventsControllerProvider.notifier).toggleFavorite(event.id, user.id, newStatus);
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
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEventDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New Event'),
      ),
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
          Icon(
            Icons.event_busy,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No events found',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Create an event to start trading.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[500]),
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
                await ref.read(eventsControllerProvider.notifier).addEvent(name, user.id);
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
