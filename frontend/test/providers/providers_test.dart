// Unit tests for the providers touched by #239.
//
// #239 found that `UserInventoryNotifier.updateItem` silently swallows API
// errors: on a failed POST it rolls the optimistic state back but neither
// rethrows nor otherwise surfaces the failure, so callers (notably the
// "Want All Missing" loop in event_detail_screen.dart) cannot tell the
// call failed. These tests pin the contract that a failing POST is
// visible to the caller (rethrown) while the optimistic state is still
// rolled back, and that the EventsController fire-and-forget toggles
// stay non-throwing (they log instead — see #239 acceptance criteria).

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';

ApiClient _apiWith({
  required http.Client client,
}) {
  final config = ConfigService();
  config.setBaseUrlForTest('http://localhost:3000');
  return ApiClient(config, client: client);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserInventoryNotifier.updateItem', () {
    test('rethrows when the POST fails (error is visible to the caller)',
        () async {
      // GET succeeds (empty inventory); POST returns 500.
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/user/inventory') {
            return http.Response('Internal Server Error', 500);
          }
          return http.Response(jsonEncode([]), 200);
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      // Prime the notifier so build() completes and state has a value.
      await container.read(inventoryProvider(1).future);

      await expectLater(
        container.read(inventoryProvider(1).notifier).updateItem(42, 'WANT', 1),
        throwsA(isA<Exception>()),
      );
    });

    test('rolls back optimistic state when the POST fails', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/user/inventory') {
            return http.Response('Internal Server Error', 500);
          }
          return http.Response(jsonEncode([]), 200);
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(inventoryProvider(1).notifier);
      await container.read(inventoryProvider(1).future);
      final before = notifier.state;

      // Swallow the rethrow; we only care about state restoration here.
      await expectLater(
        notifier.updateItem(42, 'WANT', 1),
        throwsA(isA<Exception>()),
      );

      expect(notifier.state.value, before.value,
          reason: 'optimistic state should be rolled back on failure');
    });
  });

  group('EventsController fire-and-forget toggles', () {
    test('toggleFavorite does not throw on failure', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path.endsWith('/favorite')) {
            return http.Response('Internal Server Error', 500);
          }
          return http.Response(jsonEncode([]), 200);
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      // Should complete without throwing — the caller (home_screen) relies
      // on this so it can still ref.invalidate(eventsProvider) afterward.
      await container
          .read(eventsControllerProvider.notifier)
          .toggleFavorite(1, 1, true);
    });

    test('toggleFavoriteGroup does not throw on failure', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path.endsWith('/favorite_group')) {
            return http.Response('Internal Server Error', 500);
          }
          return http.Response(jsonEncode([]), 200);
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await container
          .read(eventsControllerProvider.notifier)
          .toggleFavoriteGroup(1, 1, 'default', true);
    });
  });
}
