// Part of #230: comprehensive E2E coverage for all user-facing
// features. This file covers the Inventory area — the endpoints that
// list and update a user's per-merch inventory rows:
//   - GET  /api/v1/user/{id}/inventory  (inventoryProvider)
//   - POST /api/v1/user/inventory        (UserInventoryNotifier.updateItem)
//
// `updateItem` is exercised with each of the three legal status
// values (HAVE / WANT / TRADE) so a regression that breaks one
// status in particular is isolated to its own test. The DB unique
// key is `(user_id, merch_id, status)`, so each (merch, status)
// combo is a distinct row.
//
// Each test calls the provider method directly (not hand-built
// bodies) so a regression like #227 (provider sends snake_case but
// the backend expects camelCase) is caught here. Verifications use
// direct API calls rather than the notifier's optimistic state,
// because `updateItem` swallows API exceptions and silently rolls
// the state back — a green optimistic state would hide a 422 from
// the backend.

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

Future<int> createMerch(
  ApiClient api,
  int eventId,
  int userId,
  String tag,
) async {
  final r = await api.post('/api/v1/events/$eventId/merch', {
    'name': _uniqueName('e2e_inventory_$tag'),
    'creatorId': userId,
    'groupName': 'e2e-inventory',
  });
  return (r as Map)['id'] as int;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues(<String, Object>{});

  late ApiClient api;
  late int userId;
  late int eventId;
  late int merchHave;
  late int merchWant;
  late int merchTrade;

  setUpAll(() async {
    api = _api();
    final ready = await _waitForBackend(api);
    expect(
      ready,
      isTrue,
      reason: 'Backend not reachable; start the e2e stack first',
    );
    // Single user + event used by all the tests in this file. Use the
    // seeded moderator so the `event.create` + `merch.create` gates pass
    // (it auto-becomes the event creator).
    userId = await loginE2EModerator(api);

    final e = await api.post('/api/v1/events', {
      'name': 'E2E inventory event',
      'creatorId': userId,
    });
    eventId = (e as Map)['id'] as int;

    // Three pieces of merch, one per status. Using distinct merch
    // makes assertions simple (no need to filter by status to find
    // the row we just upserted).
    merchHave = await createMerch(api, eventId, userId, 'have');
    merchWant = await createMerch(api, eventId, userId, 'want');
    merchTrade = await createMerch(api, eventId, userId, 'trade');
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [apiClientProvider.overrideWith((ref) => api)],
    );
  }

  /// Verify a (merchId, status) row exists in the user's inventory
  /// with a positive quantity. Throws if the row is missing — the
  /// caller treats that as a test failure.
  Future<void> expectInventoryRow(int merchId, String status) async {
    final r = await api.get('/api/v1/user/$userId/inventory');
    final items = (r as List).cast<Map<String, dynamic>>();
    final match = items.firstWhere(
      (i) => i['merchId'] == merchId && i['status'] == status,
      orElse: () => throw StateError(
        'inventory row (merchId=$merchId, status=$status) not found',
      ),
    );
    expect(match['quantity'], isPositive);
  }

  test(
    'inventoryProvider GETs /user/{id}/inventory and returns a list',
    () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final items = await container.read(inventoryProvider(userId).future);
      expect(items, isA<List>());
    },
  );

  test('updateItem POSTs to /user/inventory with status=HAVE', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await container
        .read(inventoryProvider(userId).notifier)
        .updateItem(merchHave, 'HAVE', 1);

    await expectInventoryRow(merchHave, 'HAVE');
  });

  test('updateItem POSTs to /user/inventory with status=WANT', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await container
        .read(inventoryProvider(userId).notifier)
        .updateItem(merchWant, 'WANT', 1);

    await expectInventoryRow(merchWant, 'WANT');
  });

  test('updateItem POSTs to /user/inventory with status=TRADE', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await container
        .read(inventoryProvider(userId).notifier)
        .updateItem(merchTrade, 'TRADE', 1);

    await expectInventoryRow(merchTrade, 'TRADE');
  });
}
