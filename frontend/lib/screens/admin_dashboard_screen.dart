import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';

// --- Admin Providers ---
final allMatchesProvider = FutureProvider<List<TradeMatch>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/matches');
  return (json as List).map((e) => TradeMatch()..mergeFromProto3Json(e)).toList();
});

final allMerchProvider = FutureProvider<List<Merchandise>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/merch');
  return (json as List).map((e) => Merchandise()..mergeFromProto3Json(e)).toList();
});

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
        body: TabBarView(
          children: [
            _buildEventsTab(ref),
            _buildItemsTab(ref),
            _buildMatchesTab(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsTab(WidgetRef ref) {
    final eventsAsync = ref.watch(eventsProvider);

    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (events) {
        if (events.isEmpty) {
          return const Center(child: Text('No events found.'));
        }
        return ListView.builder(
          itemCount: events.length,
          itemBuilder: (context, index) {
            final event = events[index];
            return ListTile(
              title: Text(event.name),
              subtitle: Text('ID: ${event.id} | Views: ${event.uniqueViews} | Participants: ${event.activeParticipants}'),
              trailing: const Icon(Icons.chevron_right),
            );
          },
        );
      },
    );
  }

  Widget _buildItemsTab(WidgetRef ref) {
    final merchAsync = ref.watch(allMerchProvider);

    return merchAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (merchList) {
        if (merchList.isEmpty) {
          return const Center(child: Text('No merchandise found.'));
        }
        return ListView.builder(
          itemCount: merchList.length,
          itemBuilder: (context, index) {
            final merch = merchList[index];
            return ListTile(
              leading: merch.photoUrl != null && merch.photoUrl!.isNotEmpty
                  ? Image.network(merch.photoUrl!, width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.image_not_supported))
                  : const Icon(Icons.image),
              title: Text(merch.name),
              subtitle: Text('Event ID: ${merch.eventId} | Group: ${merch.groupName.isNotEmpty ? merch.groupName : "N/A"}'),
            );
          },
        );
      },
    );
  }

  Widget _buildMatchesTab(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(allMatchesProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Trigger Matching Algorithm'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () async {
              try {
                final client = ref.read(apiClientProvider);
                await client.post('/api/v1/matches/trigger', {});
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Matching triggered successfully!')));
                }
                ref.invalidate(allMatchesProvider);
              } catch (e) {
                 if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error triggering matching: $e'), backgroundColor: Colors.red));
                }
              }
            },
          ),
        ),
        Expanded(
          child: matchesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text('Error: $e')),
            data: (matches) {
              if (matches.isEmpty) {
                return const Center(child: Text('No matches found in the system.'));
              }
              return ListView.builder(
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final match = matches[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      title: Text('Match #${match.id}'),
                      subtitle: Text('Users: ${match.user1Id} & ${match.user2Id} | Status: ${match.status}'),
                      trailing: Text(match.createdAt != null ? DateTime.parse(match.createdAt!).toLocal().toString().split('.')[0] : ''),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
