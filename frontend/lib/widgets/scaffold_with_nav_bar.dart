import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';

class ScaffoldWithNavBar extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldWithNavBar({required this.navigationShell, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isAdminOrMod =
        user != null && (user.role == 'admin' || user.role == 'moderator');
    final backendHealth = ref.watch(backendHealthProvider);

    // Notification counts for badge
    final notifAsync = user != null
        ? ref.watch(notificationCountsProvider(user.id))
        : null;
    final badgeCount = notifAsync?.whenOrNull(data: (c) => c.total) ?? 0;

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.event_outlined),
        selectedIcon: Icon(Icons.event),
        label: 'Items',
      ),
      NavigationDestination(
        icon: badgeCount > 0
            ? Badge(
                label: Text('$badgeCount'),
                child: const Icon(Icons.swap_horiz_outlined),
              )
            : const Icon(Icons.swap_horiz_outlined),
        selectedIcon: badgeCount > 0
            ? Badge(
                label: Text('$badgeCount'),
                child: const Icon(Icons.swap_horiz),
              )
            : const Icon(Icons.swap_horiz),
        label: 'Matches',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Profile',
      ),
    ];

    if (isAdminOrMod) {
      destinations.add(
        const NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: 'Admin',
        ),
      );
    }

    // Show banner only when health check definitively returned false
    final bool isUnreachable = backendHealth.whenOrNull(data: (v) => !v) ?? false;

    return Scaffold(
      body: Column(
        children: [
          if (isUnreachable)
            Material(
              color: Colors.red.shade700,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'バックエンドサービスに接続できません',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => ref.invalidate(backendHealthProvider),
                        child: const Text(
                          '再試行',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex.clamp(
          0,
          destinations.length - 1,
        ),
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: destinations,
      ),
    );
  }
}
