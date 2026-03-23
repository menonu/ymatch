import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';

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
    final bool isBackendError =
        authState.hasError && authState.error is BackendUnavailableException;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Logo / Icon Placeholder
                  const Icon(
                    Icons.sync_alt_rounded,
                    size: 80,
                    color: Colors.indigo,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'ymatch',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Trade merch seamlessly.',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 48),

                  if (isBackendError) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.cloud_off,
                            size: 40,
                            color: Colors.red.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'バックエンドに接続できません',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'サービスが一時停止中の可能性があります。\nしばらく経ってから再試行してください。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('再試行'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade600,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () =>
                                ref.read(authProvider.notifier).checkLogin(),
                          ),
                        ],
                      ),
                    ),
                  ] else if (authState.isLoading)
                    const Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Logging in...'),
                      ],
                    )
                  else if (_isRestoring) ...[
                    Text(
                      'Restore Account',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _uuidController,
                      decoration: const InputDecoration(
                        labelText: 'Master Key (UUID)',
                        prefixIcon: Icon(Icons.key),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _restore,
                      child: const Text('Restore Account'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => setState(() => _isRestoring = false),
                      child: const Text('Cancel'),
                    ),
                  ] else ...[
                    ElevatedButton.icon(
                      icon: const Icon(Icons.bolt),
                      label: const Text('Start as New User'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () =>
                          ref.read(authProvider.notifier).startGuestSession(),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.restore),
                      label: const Text('Restore Existing Account'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () => setState(() => _isRestoring = true),
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
