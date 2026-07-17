// Regression test for #206: blank page after updating a username.
//
// Root cause: routerProvider did `ref.watch(authProvider)` and built a fresh
// GoRouter, so *every* auth-state change — including updateUsername, which
// only changes the user's name, not login status — rebuilt routerProvider,
// creating a new GoRouter and resetting navigation (blank page). The fix makes
// routerProvider stable (built once) and bridges auth changes to the router
// via refreshListenable + ref.read in the redirect.
//
// This test pins that contract: the router instance must NOT change across an
// auth-state change that isn't a login/logout.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/main.dart' as app;
import 'package:frontend/providers/providers.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';

ApiClient _apiWith({required http.Client client}) {
  final config = ConfigService();
  config.setBaseUrlForTest('http://localhost:3000');
  return ApiClient(config, client: client);
}

http.Response _ok(Object body) => http.Response(jsonEncode(body), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Reading routerProvider constructs AuthController (via its auth listen),
    // whose constructor auto-runs checkLogin() (reads SharedPreferences).
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'routerProvider is stable across auth state changes (no recreation on username update)',
    () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'PUT' &&
              request.url.path == '/api/v1/users/1') {
            return _ok({'id': 1, 'username': 'alice2', 'uuid': 'u-1'});
          }
          return http.Response('', 200);
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final router1 = container.read(app.routerProvider);

      // A username update writes a new AsyncValue<User?> into authProvider.
      // Before the fix this invalidated routerProvider (it ref.watch'd
      // authProvider) and rebuilt a new GoRouter. After the fix it must not.
      await container.read(authProvider.notifier).updateUsername(1, 'alice2');
      // Let the auth-listen callback (refresh notifier) settle.
      await Future<void>.delayed(Duration.zero);

      final router2 = container.read(app.routerProvider);
      expect(identical(router1, router2), isTrue);
    },
  );
}
