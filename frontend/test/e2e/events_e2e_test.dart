// Part of #230: comprehensive E2E coverage for all user-facing
// features. This file covers the Events area — the endpoints that
// create, read, update, favorite, and view events:
//   - GET    /api/v1/events                       (eventsProvider)
//   - GET    /api/v1/user/{id}/favorite_groups    (favoriteGroupsProvider)
//   - POST   /api/v1/events                       (addEvent)
//   - POST   /api/v1/events/{id}/favorite         (toggleFavorite)
//   - POST   /api/v1/events/{id}/favorite_group   (toggleFavoriteGroup)
//   - POST   /api/v1/events/{id}/view             (registerView)
//   - PUT    /api/v1/events/{id}                  (updateEvent)
//
// Note: publishEvent / publishMerch are in MerchController and will
// be covered in merch_e2e_test.dart.
//
// Note: deleteEventByCreator is NOT covered here — the endpoint it
// hits (`DELETE /api/v1/admin/events/{id}`) requires admin or
// moderator role. The provider name is misleading; this is a real
// bug (creators cannot delete their own events) that should be
// tracked separately.
//
// Each test calls the provider method directly (not hand-built
// bodies) so a regression like #227 is caught here. Verifications
// use direct API calls rather than the providers' cached state,
// because the providers don't always invalidate their caches after
// mutations (that's a separate concern from "did the request
// reach the backend with the right shape").

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

  setUpAll(() async {
    api = _api();
    final ready = await _waitForBackend(api);
    expect(
      ready,
      isTrue,
      reason: 'Backend not reachable; start the e2e stack first',
    );
    // Create a single user used by all the tests in this file. Use the
    // seeded moderator so `addEvent` (which needs `event.create`) and
    // `updateEvent` (creator-only on the moderator's events) pass.
    userId = await loginE2EModerator(api);
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [apiClientProvider.overrideWith((ref) => api)],
    );
  }

  /// Helper: read the events list and find one with the given name.
  /// Used as a "this event was just created" probe.
  Future<int> findEventIdByName(String name) async {
    final r = await api.get('/api/v1/events');
    final list = (r as List).cast<Map<String, dynamic>>();
    final match = list.firstWhere(
      (e) => e['name'] == name,
      orElse: () => throw StateError('event $name not found in /events'),
    );
    return match['id'] as int;
  }

  test('eventsProvider GETs /api/v1/events and returns a list', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    // Just verify the provider returns a list. Don't assert on the
    // contents (the DB is shared across test runs and the list is
    // global; a name-based assertion would be flaky).
    final events = await container.read(eventsProvider.future);
    expect(events, isA<List>());
  });

  test('favoriteGroupsProvider GETs /api/v1/user/{id}/favorite_groups',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final favs = await container.read(favoriteGroupsProvider.future);
    expect(favs, isA<List>());
  });

  test('addEvent POSTs to /events and the event appears in GET /events',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final name = _uniqueName('e2e_events_add');
    await container
        .read(eventsControllerProvider.notifier)
        .addEvent(name, userId);

    // No exception = the body shape was accepted. Verify via direct GET.
    final eventId = await findEventIdByName(name);
    expect(eventId, isPositive);
  });

  test('toggleFavorite POSTs to /events/{id}/favorite', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final name = _uniqueName('e2e_events_toggle');
    await container
        .read(eventsControllerProvider.notifier)
        .addEvent(name, userId);
    final eventId = await findEventIdByName(name);

    // No exception = the body shape was accepted. The event-level
    // favorite is recorded in the event_favorites table; the test
    // just verifies the request didn't 422.
    await container
        .read(eventsControllerProvider.notifier)
        .toggleFavorite(eventId, userId, true);
  });

  test('toggleFavoriteGroup POSTs to /events/{id}/favorite_group', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final name = _uniqueName('e2e_events_favgroup');
    await container
        .read(eventsControllerProvider.notifier)
        .addEvent(name, userId);
    final eventId = await findEventIdByName(name);

    await container
        .read(eventsControllerProvider.notifier)
        .toggleFavoriteGroup(eventId, userId, 'default', true);

    // The group_favorites row should be visible via /favorite_groups.
    final r = await api.get('/api/v1/user/$userId/favorite_groups');
    final groups = (r as List).cast<Map<String, dynamic>>();
    expect(
      groups.any((g) =>
          g['eventId'] == eventId && g['groupName'] == 'default'),
      isTrue,
      reason: 'group "default" should appear in /favorite_groups',
    );
  });

  test('registerView POSTs to /events/{id}/view', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final name = _uniqueName('e2e_events_view');
    await container
        .read(eventsControllerProvider.notifier)
        .addEvent(name, userId);
    final eventId = await findEventIdByName(name);

    // No exception = the body shape was accepted. The view is
    // recorded in event_views (verified separately in the backend
    // integration tests; this test focuses on the wire contract).
    await container
        .read(eventsControllerProvider.notifier)
        .registerView(eventId, userId);
  });

  test('updateEvent PUTs to /events/{id} and the new name persists',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final original = _uniqueName('e2e_events_update');
    await container
        .read(eventsControllerProvider.notifier)
        .addEvent(original, userId);
    final eventId = await findEventIdByName(original);

    final updated = '${original}_renamed';
    await container
        .read(eventsControllerProvider.notifier)
        .updateEvent(eventId, userId, updated);

    // The events provider's cache is not invalidated by updateEvent,
    // so we read the event directly via /events.
    final r = await api.get('/api/v1/events');
    final list = (r as List).cast<Map<String, dynamic>>();
    final renamed = list.firstWhere(
      (e) => e['id'] == eventId,
      orElse: () => throw StateError('event $eventId not found'),
    );
    expect(renamed['name'], updated);
  });
}
