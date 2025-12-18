import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Header
            Row(
              children: [
                const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.username, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      const Text('Master Key (UUID):', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      SelectableText(user.uuid ?? "Unknown", style: Theme.of(context).textTheme.bodySmall),
                      const Text('Save this key to restore your account!', style: TextStyle(color: Colors.red, fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 40),
            // Instructions
            Text('How to Manage Your Inventory:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('1. Go to the "Events" tab.'),
            const Text('2. Select an Event to see its Merchandise.'),
            const Text('3. Use the (+) and (-) buttons to track what you HAVE and WANT.'),
          ],
        ),
      ),
    );
  }
}
