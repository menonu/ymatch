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
    final isAdminOrMod = user != null &&
        (user.role == 'admin' || user.role == 'moderator');

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.event_outlined),
        selectedIcon: Icon(Icons.event),
        label: 'Items',
      ),
      const NavigationDestination(
        icon: Icon(Icons.swap_horiz_outlined),
        selectedIcon: Icon(Icons.swap_horiz),
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

    return Scaffold(
      body: navigationShell,
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
