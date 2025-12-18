import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../providers/providers.dart';

// Simple model for Match
class MatchModel {
  final int id;
  final int user1_id;
  final int user2_id;
  final String status;

  MatchModel({required this.id, required this.user1_id, required this.user2_id, required this.status});

  factory MatchModel.fromJson(Map<String, dynamic> json) {
    return MatchModel(
      id: json['id'],
      user1_id: json['user1_id'],
      user2_id: json['user2_id'],
      status: json['status'],
    );
  }
}

final matchesProvider = FutureProvider.family<List<MatchModel>, int>((ref, userId) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/matches/user/$userId');
  return (json as List).map((e) => MatchModel.fromJson(e)).toList();
});

class TradeListScreen extends ConsumerWidget {
  const TradeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final matchesAsync = ref.watch(matchesProvider(user.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matches'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              // Trigger matching manually
              try {
                final client = ref.read(apiClientProvider);
                await client.post('/api/v1/matches/trigger', {});
                ref.invalidate(matchesProvider(user.id));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Matching run!')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
          )
        ],
      ),
      body: matchesAsync.when(
        data: (matches) {
          if (matches.isEmpty) return const Center(child: Text('No matches yet.'));
          return ListView.builder(
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final match = matches[index];
              return ListTile(
                title: Text('Match #${match.id}'),
                subtitle: Text('Status: ${match.status}'),
                trailing: const Icon(Icons.chat),
                onTap: () => context.go('/chat/${match.id}'),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}
