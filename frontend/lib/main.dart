import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'screens/home_screen.dart';
import 'screens/event_detail_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/trade_list_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'widgets/scaffold_with_nav_bar.dart';
import 'screens/login_screen.dart';
import 'providers/providers.dart';
import 'theme/app_theme.dart';

class CustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorEventsKey = GlobalKey<NavigatorState>(debugLabel: 'events');
final _shellNavigatorMatchesKey = GlobalKey<NavigatorState>(debugLabel: 'matches');
final _shellNavigatorProfileKey = GlobalKey<NavigatorState>(debugLabel: 'profile');
final _shellNavigatorAdminKey = GlobalKey<NavigatorState>(debugLabel: 'admin');

final routerProvider = Provider<GoRouter>((ref) {
  // Assuming authProvider is defined elsewhere and provides a value that indicates auth status.
  // For example, a StreamProvider<User?> or FutureProvider<User?>
  // For this example, we'll use a dummy provider if authProvider isn't defined in the context.
  // In a real app, you'd have a proper authProvider.
  final authState = ref.watch(authProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      // If auth is loading, maybe return null or splash?
      // For now assume null value means not logged in.
      final isLoggedIn = authState.value != null;
      final isLoginRoute = state.uri.toString() == '/login';

      if (!isLoggedIn && !isLoginRoute) return '/login';
      if (isLoggedIn && isLoginRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ScaffoldWithNavBar(navigationShell: navigationShell);
        },
        branches: [
          // Events Branch
          StatefulShellBranch(
            navigatorKey: _shellNavigatorEventsKey,
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'event/:id',
                    builder: (context, state) {
                      final id = int.parse(state.pathParameters['id']!);
                      return EventDetailScreen(eventId: id);
                    },
                  ),
                ],
              ),
            ],
          ),
          // Matches Branch
          StatefulShellBranch(
            navigatorKey: _shellNavigatorMatchesKey,
            routes: [
              GoRoute(
                path: '/matches',
                builder: (context, state) => const TradeListScreen(),
                routes: [
                  GoRoute(
                    path: 'chat/:id', // Define sub-route for chat later
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) {
                      final id = int.parse(state.pathParameters['id']!);
                      return ChatScreen(matchId: id);
                    },
                  ),
                ],
              ),
            ],
          ),
          // Profile Branch
          StatefulShellBranch(
            navigatorKey: _shellNavigatorProfileKey,
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
          // Admin Branch
          StatefulShellBranch(
            navigatorKey: _shellNavigatorAdminKey,
            routes: [
              GoRoute(
                path: '/admin',
                builder: (context, state) => const AdminDashboardScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'ymatch',
      theme: AppTheme.lightTheme,
      scrollBehavior: CustomScrollBehavior(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
