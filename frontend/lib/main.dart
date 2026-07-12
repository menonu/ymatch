import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'l10n/app_localizations.dart';
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
final _shellNavigatorEventsKey = GlobalKey<NavigatorState>(
  debugLabel: 'events',
);
final _shellNavigatorMatchesKey = GlobalKey<NavigatorState>(
  debugLabel: 'matches',
);
final _shellNavigatorProfileKey = GlobalKey<NavigatorState>(
  debugLabel: 'profile',
);
final _shellNavigatorAdminKey = GlobalKey<NavigatorState>(debugLabel: 'admin');

// Bridges auth-state changes to GoRouter so the redirect is re-evaluated on
// login/logout WITHOUT rebuilding routerProvider. Rebuilding routerProvider
// would recreate the GoRouter and reset navigation — the cause of #206's
// blank page after a username update (which changes the user but not login
// status). ref.listen registers a side-effect listener that does NOT create a
// rebuild dependency, so routerProvider is built once and stays stable.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen<dynamic>(authProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: _AuthRefreshNotifier(ref),
    redirect: (context, state) {
      // Read fresh auth state on every redirect (login/logout/refresh) instead
      // of capturing a snapshot at provider-build time.
      final isLoggedIn = ref.read(authProvider).value != null;
      final isLoginRoute = state.uri.path == '/login';

      if (!isLoggedIn && !isLoginRoute) {
        // Preserve query parameters when redirecting to login
        final queryParams = state.uri.queryParameters;
        if (queryParams.isNotEmpty) {
          return Uri(path: '/login', queryParameters: queryParams).toString();
        }
        return '/login';
      }
      if (isLoggedIn && isLoginRoute) {
        // Preserve query parameters when redirecting home
        final queryParams = state.uri.queryParameters;
        if (queryParams.isNotEmpty) {
          return Uri(path: '/', queryParameters: queryParams).toString();
        }
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
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
                      // Favorite-group shortcuts pass ?group=<name> (#406).
                      final group = state.uri.queryParameters['group'];
                      // Key includes group so re-navigating to the same event
                      // with a different favorite group rebuilds the tab state.
                      return EventDetailScreen(
                        key: ValueKey('event-$id-${group ?? ''}'),
                        eventId: id,
                        initialGroupName: group,
                      );
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
      // i18n (#207): resolve UI strings from lib/l10n/*.arb. The device
      // locale is matched against supportedLocales; English is the
      // fallback for any unsupported locale (it is listed first).
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
