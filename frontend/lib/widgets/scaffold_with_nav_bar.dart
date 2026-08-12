import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'matches_nav_icon.dart';

class ScaffoldWithNavBar extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const ScaffoldWithNavBar({required this.navigationShell, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    // #551: global editor has content admin surfaces (events/merch/groups).
    final isStaff =
        user != null &&
        (user.role == 'admin' ||
            user.role == 'moderator' ||
            user.role == 'editor');
    final backendHealth = ref.watch(backendHealthProvider);

    // #535: split match lifecycle (red count, top-right) from unread chat
    // (purple count, bottom-right). Per-card Message(N) is unchanged.
    final notifAsync = user != null
        ? ref.watch(notificationCountsProvider(user.id))
        : null;
    final matchBadgeCount =
        notifAsync?.whenOrNull(
          data: (c) => c.pendingMatches + c.offersIn + c.accepted,
        ) ??
        0;
    final unreadMessageCount =
        notifAsync?.whenOrNull(data: (c) => c.unreadMessages) ?? 0;
    final l10n = AppLocalizations.of(context)!;

    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.event_outlined),
        selectedIcon: const Icon(Icons.event),
        label: l10n.navItems,
      ),
      NavigationDestination(
        icon: MatchesNavIcon(
          icon: Icons.swap_horiz_outlined,
          matchCount: matchBadgeCount,
          unreadMessageCount: unreadMessageCount,
        ),
        selectedIcon: MatchesNavIcon(
          icon: Icons.swap_horiz,
          matchCount: matchBadgeCount,
          unreadMessageCount: unreadMessageCount,
        ),
        label: l10n.navMatches,
      ),
      NavigationDestination(
        icon: const Icon(Icons.person_outline),
        selectedIcon: const Icon(Icons.person),
        label: l10n.navProfile,
      ),
    ];

    if (isStaff) {
      destinations.add(
        NavigationDestination(
          icon: const Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: const Icon(Icons.admin_panel_settings),
          label: l10n.navAdmin,
        ),
      );
    }

    // Show banner only when health check definitively returned false
    final bool isUnreachable =
        backendHealth.whenOrNull(data: (v) => !v) ?? false;

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
                      const Icon(
                        Icons.cloud_off,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.backendUnreachableBanner,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
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
                        child: Text(
                          l10n.retry,
                          style: const TextStyle(
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
