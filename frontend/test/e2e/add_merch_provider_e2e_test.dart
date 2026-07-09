// Regression test for #227.
//
// The Flutter frontend's `MerchController.addMerch` provider used to
// send snake_case request body keys (`event_id`, `photo_url`,
// `group_name`, `creator_id`). After PR #202 the backend's pbjson
// deserializer only accepts camelCase (proto3 JSON standard), so
// every call to addMerch got 422 and silently failed. The
// `add_merch_screen` showed a misleading "Added successfully"
// SnackBar because the provider swallowed the exception.
//
// This test calls `MerchController.addMerch` through the actual
// provider layer (not a hand-built body in a test helper). If
// someone reverts the body keys to snake_case, this test catches
// it. The previous E2E test (`trade_lifecycle_e2e_test.dart`)
// bypassed the provider and therefore missed the bug.
//
// The test is intentionally separate from the trade-lifecycle E2E
// so the failure surface is unambiguous: if this fails, it's the
// addMerch body shape; if trade_lifecycle fails, it's the trade
// state machine.

@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'helpers/e2e_users.dart';

ApiClient _makeApi() {
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

void main() {
  test(
    'MerchController.addMerch sends a body the backend accepts (#227)',
    () async {
      final api = _makeApi();

      // 1. Wait for the backend.
      final ready = await _waitForBackend(api);
      expect(
        ready,
        isTrue,
        reason: 'Backend not reachable; start the e2e stack first',
      );

      // 2. Set up a Riverpod container with the live API client.
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWith((ref) => api),
        ],
      );
      addTearDown(container.dispose);

      // 3. Create a user + event via the (live) API. Use the seeded
      //    moderator so the ADR 0004 `event.create` + ADR 0005
      //    `merch.create` gates pass (the moderator auto-becomes the
      //    event/creator, so addMerch below is authorized).
      final userId = await loginE2EModerator(api);
      final eventResp = await api.post('/api/v1/events', {
        'name': 'E2E 227 event ${DateTime.now().millisecondsSinceEpoch}',
        'creatorId': userId,
      });
      final eventId = (eventResp as Map)['id'] as int;

      // 4. Call the actual provider method. This is the exact path
      //    `add_merch_screen.dart` takes. If the provider sends
      //    snake_case, this throws (or the call returns 422 and
      //    the rethrow propagates here, failing the test).
      await container
          .read(merchControllerProvider.notifier)
          .addMerch(
            eventId,
            'Test merch',
            '',
            'e2e-227-group',
            userId,
          );

      // 5. THE ASSERTION: the merch was actually created.
      //    This is what the user sees in the UI (or rather, what
      //    they should see — the bug was that nothing appeared).
      final merchList = await api.get(
        '/api/v1/events/$eventId/merch?user_id=$userId',
      );
      final merch = (merchList as List).cast<Map<String, dynamic>>();
      expect(
        merch.length,
        1,
        reason:
            'addMerch succeeded but the merch did not appear in GET /api/v1/events/.../merch',
      );
      expect(merch.first['name'], 'Test merch');
      expect(merch.first['groupName'], 'e2e-227-group');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
