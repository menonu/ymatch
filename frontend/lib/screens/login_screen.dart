import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _uuidController = TextEditingController();
  bool _isRestoring = false;

  @override
  void dispose() {
    _uuidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 300,
              child: authState.isLoading
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Logging in as Guest...'),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Welcome to ymatch', style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 24),
                        if (_isRestoring) ...[
                          TextField(
                            controller: _uuidController,
                            decoration: const InputDecoration(labelText: 'Enter Master Key (UUID)'),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _restore,
                            child: const Text('Restore Account'),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _isRestoring = false),
                            child: const Text('Cancel'),
                          ),
                        ] else ...[
                          const Text('Creating your secure guest account...', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          // Manual trigger if auto-login fails or takes time
                          ElevatedButton(
                            onPressed: () => ref.read(authProvider.notifier).startGuestSession(),
                            child: const Text('Start'),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => setState(() => _isRestoring = true),
                            child: const Text('I have a Master Key (Restore)'),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _restore() async {
    final uuid = _uuidController.text.trim();
    if (uuid.isNotEmpty) {
      await ref.read(authProvider.notifier).restoreAccount(uuid);
    }
  }
}
