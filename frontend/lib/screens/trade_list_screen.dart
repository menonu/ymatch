import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

final matchesProvider = FutureProvider.family<List<TradeMatch>, int>((ref, userId) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/matches/user/$userId');
  return (json as List).map((e) => TradeMatch()..mergeFromProto3Json(e)).toList();
});

class TradeListScreen extends ConsumerWidget {
  const TradeListScreen({super.key});

  Future<void> _updateStatus(BuildContext context, WidgetRef ref, int userId, int matchId, String newStatus) async {
    try {
      final client = ref.read(apiClientProvider);
      await client.post('/api/v1/matches/$matchId/status', {'status': newStatus});
      ref.invalidate(matchesProvider(userId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final matchesAsync = ref.watch(matchesProvider(user.id));

    return Scaffold(
      appBar: AppBar(),
      body: matchesAsync.when(
        data: (matches) {
          if (matches.isEmpty) return _buildEmptyState(context);

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final match = matches[index];
              final isPending = match.status == 'PENDING';
              final isAccepted = match.status == 'ACCEPTED';

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    // Navigate to chat if it's an active trade
                    if (isPending || isAccepted) {
                      context.go('/matches/chat/${match.id}');
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppTheme.secondaryColor.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.handshake_outlined, color: AppTheme.secondaryColor),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Trade Match #${match.id}',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(match.status).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      match.status,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _getStatusColor(match.status),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isPending || isAccepted)
                              const Icon(Icons.chat_bubble_outline, color: Colors.grey),
                          ],
                        ),
                        // Show what is being traded
                        if (match.userHaves.isNotEmpty || match.userWants.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text('You Give:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                          ...match.userHaves.map((item) => Text('• ${item.merchName} (Qty: ${item.quantity})', style: const TextStyle(fontSize: 12))),
                          const SizedBox(height: 4),
                          Text('You Receive:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                          ...match.userWants.map((item) => Text('• ${item.merchName} (Qty: ${item.quantity})', style: const TextStyle(fontSize: 12))),
                        ],
                        // Action Buttons based on lifecycle
                        if (isPending) ...[
                          const SizedBox(height: 16),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => _updateStatus(context, ref, user.id, match.id, 'REJECTED'),
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                child: const Text('Reject'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () async {
                                  // Show a dialog to confirm the specific items
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Confirm Trade Offer'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('You will give:'),
                                          ...match.userHaves.map((i) => Text('• ${i.merchName}')),
                                          const SizedBox(height: 16),
                                          const Text('You will receive:'),
                                          ...match.userWants.map((i) => Text('• ${i.merchName}')),
                                          const SizedBox(height: 16),
                                          const Text('Are you sure you want to accept this match?', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
                                      ],
                                    ),
                                  );
                                  if (confirm == true && context.mounted) {
                                    _updateStatus(context, ref, user.id, match.id, 'ACCEPTED');
                                  }
                                },
                                child: const Text('Accept Match'),
                              ),
                            ],
                          )
                        ] else if (isAccepted) ...[
                          const SizedBox(height: 16),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => _updateStatus(context, ref, user.id, match.id, 'REJECTED'),
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                child: const Text('Cancel Trade'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () => _updateStatus(context, ref, user.id, match.id, 'COMPLETED'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                child: const Text('Mark as Completed'),
                              ),
                            ],
                          )
                        ]
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
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'PENDING':
        return Colors.orange;
      case 'ACCEPTED':
        return Colors.blue;
      case 'COMPLETED':
        return Colors.green;
      case 'REJECTED':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swap_horiz, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No matches found',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Keep adding items to your inventory.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
