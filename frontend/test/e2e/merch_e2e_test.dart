// Part of #230: comprehensive E2E coverage for all user-facing
// features. This file covers the Merch area — the endpoints that
// create, read, update, and delete merch:
//   - GET    /api/v1/events/{id}/merch       (merchProvider)
//   - POST   /api/v1/events/{id}/merch       (addMerch)
//   - PUT    /api/v1/events/{id}/merch/{id}  (updateMerch)
//   - DELETE /api/v1/events/{id}/merch/{id}  (deleteMerchByCreator)
//
// Note: `MerchController.publishMerch` is defined but never called
// from the UI (dead code), so it is not covered here. The handler
// it would hit (`/events/{id}/merch/{id}/publish`) is exercised by
// the backend integration tests.
//
// Each test calls the provider method directly (not hand-built
// bodies) so a regression like #227 is caught here. Verifications
// use direct API calls.

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
  late int userId;
  late int eventId;

  setUpAll(() async {
    api = _api();
    final ready = await _waitForBackend(api);
    expect(
      ready,
      isTrue,
      reason: 'Backend not reachable; start the e2e stack first',
    );
    // Single user + event used by all the tests in this file. Use the
    // seeded moderator so the ADR 0004 `event.create` + ADR 0005
    // `merch.create` gates pass; the moderator auto-becomes the event
    // creator, so addMerch/updateMerch/deleteMerch below are authorized.
    userId = await loginE2EModerator(api);

    final e = await api.post('/api/v1/events', {
      'name': 'E2E merch event',
      'creatorId': userId,
    });
    eventId = (e as Map)['id'] as int;
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [apiClientProvider.overrideWith((ref) => api)],
    );
  }

  Future<int> addMerch(ProviderContainer container, String name) async {
    await container
        .read(merchControllerProvider.notifier)
        .addMerch(eventId, name, '', 'e2e-group', userId);

    // Find the newly-created merch (the merch provider is cached).
    final list = await api.get('/api/v1/events/$eventId/merch?user_id=$userId');
    final merch = (list as List).cast<Map<String, dynamic>>();
    final match = merch.firstWhere(
      (m) => m['name'] == name,
      orElse: () => throw StateError('merch $name not found'),
    );
    return match['id'] as int;
  }

  test('merchProvider GETs /events/{id}/merch and returns a list', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final merch = await container.read(merchProvider(eventId).future);
    expect(merch, isA<List>());
  });

  test('addMerch POSTs to /events/{id}/merch and the merch appears', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final name = _uniqueName('e2e_merch_add');
    final merchId = await addMerch(container, name);
    expect(merchId, isPositive);
  });

  test(
    'updateMerch PUTs to /events/{id}/merch/{id} and the new name persists',
    () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final name = _uniqueName('e2e_merch_update');
      final merchId = await addMerch(container, name);

      final updated = '${name}_renamed';
      await container
          .read(merchControllerProvider.notifier)
          .updateMerch(eventId, merchId, userId, name: updated);

      // merchProvider is cached, so verify via direct API.
      final list = await api.get(
        '/api/v1/events/$eventId/merch?user_id=$userId',
      );
      final merch = (list as List).cast<Map<String, dynamic>>();
      final renamed = merch.firstWhere(
        (m) => m['id'] == merchId,
        orElse: () => throw StateError('merch $merchId not found'),
      );
      expect(renamed['name'], updated);
    },
  );

  test(
    // ADR 0008: delete is soft-delete only. The creator is a holder, so
    // the row remains on GET /events/{id}/merch marked isDeleted=true.
    'deleteMerchByCreator DELETEs /events/{id}/merch/{id} and soft-deletes it',
    () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final name = _uniqueName('e2e_merch_delete');
      final merchId = await addMerch(container, name);

      await container
          .read(merchControllerProvider.notifier)
          .deleteMerchByCreator(eventId, merchId, userId);

      final list = await api.get(
        '/api/v1/events/$eventId/merch?user_id=$userId',
      );
      final merch = (list as List).cast<Map<String, dynamic>>();
      final deleted = merch.where((m) => m['id'] == merchId).toList();
      expect(
        deleted,
        hasLength(1),
        reason: 'creator (holder) still sees soft-deleted merch (ADR 0008)',
      );
      expect(
        deleted.single['isDeleted'],
        isTrue,
        reason: 'soft-deleted merch is marked isDeleted for holders',
      );
      expect(
        deleted.single['tradeEnabled'],
        isFalse,
        reason: 'soft-delete always disables trade',
      );
    },
  );
}
