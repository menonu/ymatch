import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';
import '../widgets/how_to_trade.dart';

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
    final l10n = AppLocalizations.of(context)!;
    final bool isBackendError =
        authState.hasError && authState.error is BackendUnavailableException;
    // The Profile-tab pointer only makes sense on the default (new-user)
    // landing state — hide it during backend error, loading, or restore.
    final bool showGuidePointer =
        !isBackendError && !authState.isLoading && !_isRestoring;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
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
                          l10n.appName,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                                letterSpacing: -1,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.loginTagline,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: Colors.grey[600]),
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
                                  l10n.loginBackendErrorTitle,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.loginBackendErrorBody,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red.shade600,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.refresh),
                                  label: Text(l10n.retry),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade600,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () => ref
                                      .read(authProvider.notifier)
                                      .checkLogin(),
                                ),
                              ],
                            ),
                          ),
                        ] else if (authState.isLoading)
                          Column(
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              Text(l10n.loggingIn),
                            ],
                          )
                        else if (_isRestoring) ...[
                          Text(
                            l10n.restoreAccount,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _uuidController,
                            decoration: InputDecoration(
                              labelText: l10n.masterKeyUuid,
                              prefixIcon: const Icon(Icons.key),
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _restore,
                            child: Text(l10n.restoreAccount),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () =>
                                setState(() => _isRestoring = false),
                            child: Text(l10n.cancel),
                          ),
                        ] else ...[
                          ElevatedButton.icon(
                            icon: const Icon(Icons.bolt),
                            label: Text(l10n.startAsNewUser),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: () => ref
                                .read(authProvider.notifier)
                                .startGuestSession(),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.restore),
                            label: Text(l10n.restoreExistingAccount),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: () =>
                                setState(() => _isRestoring = true),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Point brand-new users at the How to Trade guide, which lives
            // behind the Profile tab. A long arrow (drawn inside the virtual
            // tab bar below) points down at the Profile tab, rendered in the
            // bottom-nav area — the same area the real nav bar occupies after
            // login (#336).
            if (showGuidePointer)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
                child: Text(
                  l10n.howToHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ),
          ],
        ),
      ),
      // Virtual preview of the bottom-nav Profile tab, shown where the real
      // nav bar will be after login. Tapping it does not open the guide — it
      // only tells the user the tab is available after login (#336).
      bottomNavigationBar: showGuidePointer
          ? const VirtualProfileTabBar()
          : null,
    );
  }

  Future<void> _restore() async {
    final uuid = _uuidController.text.trim();
    if (uuid.isNotEmpty) {
      await ref.read(authProvider.notifier).restoreAccount(uuid);
    }
  }
}
