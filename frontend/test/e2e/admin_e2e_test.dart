// Part of #230: comprehensive E2E coverage for all user-facing
// features. This file covers the Admin area — endpoints that require
// an admin or moderator role:
//   - GET    /api/v1/admin/merch         (adminMerchProvider)
//   - GET    /api/v1/admin/matches       (adminMatchesProvider)
//   - GET    /api/v1/users               (adminUsersProvider)
//   - POST   /api/v1/admin/users/{id}/ban    (AdminController.banUser)
//   - POST   /api/v1/admin/users/{id}/unban  (AdminController.unbanUser)
//   - POST   /api/v1/admin/users/{id}/role   (AdminController.updateUserRole)
//   - DELETE /api/v1/admin/events/{id}   (screen-level in admin_dashboard_screen.dart)
//   - DELETE /api/v1/admin/merch/{id}    (screen-level in admin_dashboard_screen.dart)
//
// The GET providers are covered first because they are the only
// call sites for those endpoints. The mutation tests then exercise
// the AdminController and the screen-level direct deletes. Ban/unban
// are paired in a single test to avoid leaving a banned user behind.
//
// All calls go through the same client/provider code the UI uses,
// with camelCase request bodies, so a regression like #227 is
// caught here.

@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/e2e_users.dart';

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

String _uniqueName(String prefix) =>
    '${prefix}_${DateTime.now().microsecondsSinceEpoch}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues(<String, Object>{});

  late ApiClient api;
  late int adminUserId;

  setUpAll(() async {
    api = _api();
    final ready = await _waitForBackend(api);
    expect(
      ready,
      isTrue,
      reason: 'Backend not reachable; start the e2e stack first',
    );

    // Log in as the seeded admin (scripts/e2e-seed.sql). The admin
    // endpoints require an admin caller; RBAC checks the `user_roles`
    // table (not `users.role`), so the seed installs the global/admin
    // row — a plain `users.role` UPDATE is a no-op for authz.
    adminUserId = await loginE2EAdmin(api);
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [apiClientProvider.overrideWith((ref) => api)],
    );
  }

  /// Create a regular user for ban/role/delete tests.
  Future<int> createRegularUser() async {
    final r = await api.post('/api/v1/auth/guest', {
      'uuid': 'e2e_admin_target_${DateTime.now().microsecondsSinceEpoch}',
      'deviceToken': 'e2e-admin-target',
    });
    return (r as Map)['id'] as int;
  }

  /// Create an event (no merch) owned by the seeded moderator, for the
  /// admin-delete-event test. The moderator has `event.create`, so the
  /// fixture passes the ADR 0004 gate; the admin then deletes the
  /// moderator's event (a "delete another user's resource" path).
  Future<({int userId, int eventId})> createEventOnly() async {
    final userId = await loginE2EModerator(api);

    final event = await api.post('/api/v1/events', {
      'name': _uniqueName('e2e_admin_event'),
      'creatorId': userId,
    });
    final eventId = (event as Map)['id'] as int;

    return (userId: userId, eventId: eventId);
  }

  /// Create an event + merch owned by the seeded moderator, for the
  /// admin-delete-merch test. The moderator has `event.create` +
  /// `merch.create.any` (and auto-becomes the event creator), so the
  /// fixtures pass the ADR 0004/0005 gates; the admin then deletes the
  /// moderator's merch.
  Future<({int userId, int eventId, int merchId})> createEventAndMerch() async {
    final userId = await loginE2EModerator(api);

    final event = await api.post('/api/v1/events', {
      'name': _uniqueName('e2e_admin_event'),
      'creatorId': userId,
    });
    final eventId = (event as Map)['id'] as int;

    final merch = await api.post('/api/v1/events/$eventId/merch', {
      'name': _uniqueName('e2e_admin_merch'),
      'creatorId': userId,
      'groupName': 'e2e-admin',
    });
    final merchId = (merch as Map)['id'] as int;

    return (userId: userId, eventId: eventId, merchId: merchId);
  }

  test('adminMerchProvider GETs /api/v1/admin/merch and returns a list',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final items = await container.read(adminMerchProvider.future);
    expect(items, isA<List>(),
        reason: 'adminMerchProvider should return a list');
  });

  test('adminMatchesProvider GETs /api/v1/admin/matches and returns a list',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final matches = await container.read(adminMatchesProvider.future);
    expect(matches, isA<List>(),
        reason: 'adminMatchesProvider should return a list');
  });

  test('adminUsersProvider GETs /api/v1/users and returns a list',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final users = await container.read(adminUsersProvider.future);
    expect(users, isA<List>(),
        reason: 'adminUsersProvider should return a list');
  });

  test('AdminController.banUser bans and unbanUser unbans the target',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final targetId = await createRegularUser();

    await container
        .read(adminControllerProvider.notifier)
        .banUser(targetId, adminUserId, reason: 'e2e test ban');

    final banned = await api.get('/api/v1/admin/users/$targetId');
    expect((banned as Map)['isBanned'], isTrue,
        reason: 'target user should be banned');

    await container
        .read(adminControllerProvider.notifier)
        .unbanUser(targetId, adminUserId);

    final unbanned = await api.get('/api/v1/admin/users/$targetId');
    expect((unbanned as Map)['isBanned'], isFalse,
        reason: 'target user should be unbanned');
  });

  test('AdminController.updateUserRole changes the target role',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final targetId = await createRegularUser();

    await container
        .read(adminControllerProvider.notifier)
        .updateUserRole(targetId, adminUserId, 'moderator');

    final updated = await api.get('/api/v1/admin/users/$targetId');
    expect((updated as Map)['role'], 'moderator');
  });

  test(
      'admin dashboard DELETE /api/v1/admin/events/{id} removes the event',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    // Use an event with no merch so the DB FK on merchandise doesn't
    // block the delete.
    final ids = await createEventOnly();

    // Same direct delete the admin dashboard screen uses.
    await api.delete(
      '/api/v1/admin/events/${ids.eventId}?user_id=$adminUserId',
    );

    // Verify the event is gone via the public events list.
    final allEvents = (await api.get('/api/v1/events') as List)
        .cast<Map<String, dynamic>>();
    expect(
      allEvents.any((e) => e['id'] == ids.eventId),
      isFalse,
      reason: 'event should be deleted',
    );
  });

  test(
      'admin dashboard DELETE /api/v1/admin/merch/{id} removes the merch',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final ids = await createEventAndMerch();

    await api.delete(
      '/api/v1/admin/merch/${ids.merchId}?user_id=$adminUserId',
    );

    final allMerch = await api.get('/api/v1/admin/merch');
    final merchList = (allMerch as List).cast<Map<String, dynamic>>();
    expect(
      merchList.any((m) => m['id'] == ids.merchId),
      isFalse,
      reason: 'merch should be deleted',
    );
  });
}
