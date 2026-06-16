// Part of #230: comprehensive E2E coverage for all user-facing
// features. This file covers the Auth area — four endpoints:
//   - POST /api/v1/auth/guest  (guestLogin)
//   - POST /api/v1/auth/login   (login)
//   - POST /api/v1/auth/signup  (signup)
//   - PUT  /api/v1/users/{id}   (updateUsername)
//
// Each test calls the provider method directly (not hand-built
// bodies) so a regression like #227 (provider sends snake_case but
// the backend expects camelCase) is caught here.

@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

ApiClient _api() {
  final config = ConfigService();
  config.setBaseUrlForTest(
    Platform.environment['E2E_API_URL'] ?? 'http://localhost:3000',
  );
  return ApiClient(config);
}

Future<bool> _waitForBackend(ApiClient api) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final r = await api.get('/api/v1/system/status');
      if (r is Map && r['backend_version'] != null) return true;
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

String _uniqueUsername() =>
    'e2e_auth_${DateTime.now().microsecondsSinceEpoch}';

void main() {
  // AuthController reads SharedPreferences and Uri.base in its
  // constructor, so the Flutter binding must be initialized even
  // though this is a non-widget test. But TestWidgetsFlutterBinding
  // installs an HttpOverrides that returns 400 for every request
  // — useful for unit tests, fatal for E2E. We initialize the
  // binding, then immediately replace the HttpOverrides with the
  // default (no-op) so real HTTP works.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues(<String, Object>{});

  late ApiClient api;
  setUpAll(() async {
    api = _api();
    final ready = await _waitForBackend(api);
    expect(
      ready,
      isTrue,
      reason: 'Backend not reachable; start the e2e stack first',
    );
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [apiClientProvider.overrideWith((ref) => api)],
    );
  }

  test('AuthController.guestLogin posts to /auth/guest and sets the user',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final uuid =
        'e2e-auth-guest-${DateTime.now().microsecondsSinceEpoch}';
    await container.read(authProvider.notifier).guestLogin(uuid);

    final state = container.read(authProvider);
    expect(state.hasValue, isTrue);
    expect(state.value, isNotNull);
    expect(state.value!.id, isPositive);
    expect(state.value!.uuid, uuid);
  });

  test('AuthController.signup posts to /auth/signup and sets the user',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final username = _uniqueUsername();
    await container
        .read(authProvider.notifier)
        .signup(username, 'test-password-1234');

    final state = container.read(authProvider);
    expect(state.hasValue, isTrue);
    expect(state.value, isNotNull);
    expect(state.value!.username, username);
  });

  test('AuthController.login posts to /auth/login with the right body',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final username = _uniqueUsername();
    final password = 'test-password-1234';

    // Signup first (login needs an existing user).
    await container.read(authProvider.notifier).signup(username, password);
    final afterSignup = container.read(authProvider).value;
    expect(afterSignup, isNotNull);

    // Now logout (clears state) and login.
    container.read(authProvider.notifier).logout();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(authProvider).value, isNull,
        reason: 'logout should clear the user');

    await container
        .read(authProvider.notifier)
        .login(username, password);
    final afterLogin = container.read(authProvider);
    expect(afterLogin.hasValue, isTrue);
    expect(afterLogin.value, isNotNull);
    expect(afterLogin.value!.id, afterSignup!.id);
    expect(afterLogin.value!.username, username);
  });

  test('AuthController.updateUsername Puts to /users/{id} and updates the state',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    // Use guest login (easiest way to get a userId without signup).
    final uuid = 'e2e-auth-upd-${DateTime.now().microsecondsSinceEpoch}';
    await container.read(authProvider.notifier).guestLogin(uuid);
    final userId = container.read(authProvider).value!.id;

    final newUsername = _uniqueUsername();
    await container
        .read(authProvider.notifier)
        .updateUsername(userId, newUsername);

    final state = container.read(authProvider);
    expect(state.hasValue, isTrue);
    expect(state.value, isNotNull);
    expect(state.value!.username, newUsername);
    expect(state.value!.id, userId);
  });
}
