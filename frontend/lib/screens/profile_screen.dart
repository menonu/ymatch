import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _editingUsername = false;
  late TextEditingController _usernameController;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _saveUsername(int userId) async {
    final newName = _usernameController.text.trim();
    if (newName.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    try {
      await ref.read(authProvider.notifier).updateUsername(userId, newName);
      if (mounted) {
        setState(() => _editingUsername = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.usernameUpdated)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToUpdateUsername(e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final l10n = AppLocalizations.of(context)!;
    if (user == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile Card
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1),
                      child: Icon(
                        Icons.person,
                        size: 48,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Username row with edit support
                    if (_editingUsername)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _usernameController,
                              autofocus: true,
                              decoration: InputDecoration(
                                labelText: l10n.username,
                                isDense: true,
                              ),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _saveUsername(user.id),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.check),
                            color: Colors.green,
                            onPressed: () => _saveUsername(user.id),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                setState(() => _editingUsername = false),
                          ),
                        ],
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            user.username,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            color: Colors.grey,
                            tooltip: l10n.editUsername,
                            onPressed: () {
                              _usernameController.text = user.username;
                              setState(() => _editingUsername = true);
                            },
                          ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                l10n.masterKeyUuid,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 20),
                                color: Theme.of(context).colorScheme.primary,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () async {
                                  if (user.hasUuid() && user.uuid.isNotEmpty) {
                                    await Clipboard.setData(
                                      ClipboardData(text: user.uuid),
                                    );
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(l10n.masterKeyCopied),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            user.hasUuid() && user.uuid.isNotEmpty
                                ? user.uuid
                                : l10n.unknown,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l10n.saveKeyWarning,
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Instructions Card
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.help_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.howToTrade,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildInstructionStep(context, '1', l10n.tradeStep1),
                    _buildInstructionStep(context, '2', l10n.tradeStep2),
                    _buildInstructionStep(context, '3', l10n.tradeStep3),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            OutlinedButton.icon(
              icon: const Icon(Icons.logout),
              label: Text(l10n.logOut),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () => ref.read(authProvider.notifier).logout(),
            ),
            const SizedBox(height: 16),
            _buildRevisionInfo(context, ref),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(BuildContext context, String step, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              step,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _buildRevisionInfo(BuildContext context, WidgetRef ref) {
    const frontendRev = String.fromEnvironment('GIT_HASH', defaultValue: 'dev');
    final statusAsync = ref.watch(backendSystemStatusProvider);
    final backendRev = statusAsync.when(
      data: (data) => (data['backend_version'] as String?) ?? 'unknown',
      loading: () => '...',
      error: (_, __) => 'error',
    );
    final l10n = AppLocalizations.of(context)!;
    return Text(
      l10n.revisionInfo(_shortHash(frontendRev), _shortHash(backendRev)),
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
    );
  }

  String _shortHash(String hash) {
    if (hash.length > 7) return hash.substring(0, 7);
    return hash;
  }
}
