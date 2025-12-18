import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../providers/providers.dart';
import '../models/models.dart';

final matchesProvider = FutureProvider.family<List<TradeMatch>, int>((ref, userId) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/matches/user/$userId');
  return (json as List).map((e) => TradeMatch()..mergeFromProto3Json(e)).toList();
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
