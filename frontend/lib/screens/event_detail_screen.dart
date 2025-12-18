import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/models.dart';

class EventDetailScreen extends ConsumerWidget {
  final int eventId;

  const EventDetailScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchAsync = ref.watch(merchProvider(eventId));
    final user = ref.watch(currentUserProvider);
    final inventoryAsync = user != null ? ref.watch(inventoryProvider(user.id)) : null;

    return Scaffold(
      appBar: AppBar(title: Text('Event $eventId Inventory')),
      body: merchAsync.when(
        data: (merch) {
          if (merch.isEmpty) return const Center(child: Text('No merchandise found. Add some!'));

          // Build map of user's inventory for quick lookup (multi-map for HAVE/WANT)
          final Map<int, Map<String, int>> inventoryLookup = {};
          if (inventoryAsync != null && inventoryAsync.hasValue) {
            for (final inv in inventoryAsync.value!) {
              inventoryLookup.putIfAbsent(inv.merchId, () => {})[inv.status] = inv.quantity;
            }
          }

          return ListView.builder(
            itemCount: merch.length,
            itemBuilder: (context, index) {
              final item = merch[index];
              final merchInv = inventoryLookup[item.id] ?? {};
              final haveQty = merchInv['HAVE'] ?? 0;
              final wantQty = merchInv['WANT'] ?? 0;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      // Item Photo
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: item.photoUrl != null && item.photoUrl!.isNotEmpty
                            ? Image.network(item.photoUrl!, width: 70, height: 70, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 70))
                            : Container(width: 70, height: 70, color: Colors.grey[200], child: const Icon(Icons.image, size: 40, color: Colors.grey)),
                      ),
                      const SizedBox(width: 16),
                      // Item Name
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(item.name,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                            const SizedBox(height: 4),
                            Text('Event Merch', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          ],
                        ),
                      ),
                      // Inventory Controls
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                           _buildStepper(
                            label: 'HAVE',
                            color: Colors.teal,
                            qty: haveQty,
                            onUpdate: (newQty) => ref.read(inventoryProvider(user!.id).notifier).updateItem(item.id, 'HAVE', newQty),
                          ),
                          const SizedBox(width: 8),
                          _buildStepper(
                            label: 'WANT',
                            color: Colors.orangeAccent,
                            qty: wantQty,
                            onUpdate: (newQty) => ref.read(inventoryProvider(user!.id).notifier).updateItem(item.id, 'WANT', newQty),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddMerchDialog(context, ref, eventId),
        label: const Text('Add Merch'),
        icon: const Icon(Icons.add_photo_alternate),
      ),
    );
  }

  Widget _buildStepper({
    required String label,
    required Color color,
    required int qty,
    required Function(int) onUpdate,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 4),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StepperButton(
                icon: Icons.add,
                color: color,
                onTap: () => onUpdate(qty + 1),
                label: 'Increase $label',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('$qty', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ),
              _StepperButton(
                icon: Icons.remove,
                color: color,
                onTap: qty > 0 ? () => onUpdate(qty - 1) : null,
                label: 'Decrease $label',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String label;

  const _StepperButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      enabled: onTap != null,
      child: Material(
        color: onTap != null ? color : Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: 44, // Large hit target
            height: 44,
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}


  void _showAddMerchDialog(BuildContext context, WidgetRef ref, int eventId) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Merchandise'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Item Name'),
            ),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: 'Photo URL (Optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                await ref.read(merchControllerProvider.notifier).addMerch(eventId, name, urlController.text.trim());
                ref.invalidate(merchProvider(eventId));
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
