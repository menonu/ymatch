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

ApiClient _apiWith({required http.Client client}) {
  final config = ConfigService();
  config.setBaseUrlForTest('http://localhost:3000');
  return ApiClient(config, client: client);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserInventoryNotifier.updateItem', () {
    test(
      'rethrows when the POST fails (error is visible to the caller)',
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
          container
              .read(inventoryProvider(1).notifier)
              .updateItem(42, 'WANT', 1),
          throwsA(isA<Exception>()),
        );
      },
    );

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

      expect(
        notifier.state.value,
        before.value,
        reason: 'optimistic state should be rolled back on failure',
      );
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

  // #128: group create/update payloads and error surfacing for the frontend
  // group description UI.
  group('GroupController (#128)', () {
    test(
      'createGroup posts camelCase proto3 JSON and returns the group',
      () async {
        String? capturedBody;
        String? capturedPath;
        final api = _apiWith(
          client: MockClient((request) async {
            if (request.method == 'POST' &&
                request.url.path == '/api/v1/events/7/groups') {
              capturedBody = request.body;
              capturedPath = request.url.path;
              return http.Response(
                jsonEncode({
                  'id': 3,
                  'eventId': 7,
                  'groupName': 'Pins',
                  'description': 'enamel pins',
                  'createdBy': 1,
                }),
                200,
              );
            }
            return http.Response(jsonEncode([]), 200);
          }),
        );
        final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWith((ref) => api)],
        );
        addTearDown(container.dispose);

        final group = await container
            .read(groupControllerProvider.notifier)
            .createGroup(
              eventId: 7,
              userId: 1,
              groupName: 'Pins',
              description: 'enamel pins',
            );

        expect(capturedPath, '/api/v1/events/7/groups');
        final decoded = jsonDecode(capturedBody!) as Map<String, dynamic>;
        expect(decoded, containsPair('eventId', 7));
        expect(decoded, containsPair('userId', 1));
        expect(decoded, containsPair('groupName', 'Pins'));
        expect(decoded, containsPair('description', 'enamel pins'));
        expect(decoded, isNot(contains('group_name')));
        expect(group.groupName, 'Pins');
        expect(group.description, 'enamel pins');
      },
    );

    test(
      'updateGroup URL-encodes the group name and rethrows on failure',
      () async {
        String? capturedPath;
        final api = _apiWith(
          client: MockClient((request) async {
            if (request.method == 'PUT' &&
                request.url.path.contains('/groups/')) {
              capturedPath = request.url.path;
              return http.Response('Forbidden', 403);
            }
            return http.Response(jsonEncode([]), 200);
          }),
        );
        final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWith((ref) => api)],
        );
        addTearDown(container.dispose);

        await expectLater(
          container
              .read(groupControllerProvider.notifier)
              .updateGroup(
                eventId: 7,
                userId: 1,
                groupName: 'Key Chains',
                description: 'updated',
              ),
          throwsA(isA<Exception>()),
        );
        // Space encoded as %20 (or + depending on encoder — encodeComponent uses %20).
        expect(capturedPath, '/api/v1/events/7/groups/Key%20Chains');
      },
    );

    test(
      'updateGroup sends photoUrl when updatePhoto is true (#404)',
      () async {
        String? capturedBody;
        final api = _apiWith(
          client: MockClient((request) async {
            if (request.method == 'PUT' &&
                request.url.path.contains('/groups/')) {
              capturedBody = request.body;
              return http.Response(
                jsonEncode({
                  'id': 1,
                  'eventId': 7,
                  'groupName': 'Pins',
                  'description': 'd',
                  'photoUrl': 'https://cdn.example/g.png',
                }),
                200,
              );
            }
            return http.Response(jsonEncode([]), 200);
          }),
        );
        final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWith((ref) => api)],
        );
        addTearDown(container.dispose);

        final group = await container
            .read(groupControllerProvider.notifier)
            .updateGroup(
              eventId: 7,
              userId: 1,
              groupName: 'Pins',
              description: 'd',
              photoUrl: 'https://cdn.example/g.png',
              updatePhoto: true,
            );

        final decoded = jsonDecode(capturedBody!) as Map<String, dynamic>;
        expect(decoded, containsPair('photoUrl', 'https://cdn.example/g.png'));
        expect(group.photoUrl, 'https://cdn.example/g.png');
      },
    );

    test(
      'updateGroup omits photoUrl when updatePhoto is false (#404)',
      () async {
        String? capturedBody;
        final api = _apiWith(
          client: MockClient((request) async {
            if (request.method == 'PUT' &&
                request.url.path.contains('/groups/')) {
              capturedBody = request.body;
              return http.Response(
                jsonEncode({
                  'id': 1,
                  'eventId': 7,
                  'groupName': 'Pins',
                  'description': 'd',
                }),
                200,
              );
            }
            return http.Response(jsonEncode([]), 200);
          }),
        );
        final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWith((ref) => api)],
        );
        addTearDown(container.dispose);

        await container
            .read(groupControllerProvider.notifier)
            .updateGroup(
              eventId: 7,
              userId: 1,
              groupName: 'Pins',
              description: 'd',
            );

        final decoded = jsonDecode(capturedBody!) as Map<String, dynamic>;
        expect(decoded, isNot(contains('photoUrl')));
      },
    );

    test('eventGroupsProvider parses ListGroupsResponse', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/events/7/groups') {
            return http.Response(
              jsonEncode({
                'groups': [
                  {
                    'id': 1,
                    'eventId': 7,
                    'groupName': 'Pins',
                    'description': 'nice',
                    'createdBy': 2,
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(jsonEncode([]), 200);
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final groups = await container.read(eventGroupsProvider(7).future);
      expect(groups, hasLength(1));
      expect(groups.first.groupName, 'Pins');
      expect(groups.first.createdBy, 2);
    });
  });

  // #215: request payloads must be built from generated protobuf types and
  // serialized via toProto3Json(), which emits camelCase keys. These tests
  // pin that contract so the payloads can't silently regress to hand-written
  // snake_case maps.
  group('Proto3 JSON payloads (#215)', () {
    test(
      'addEvent sends camelCase proto3 JSON (creatorId, not creator_id)',
      () async {
        String? capturedBody;
        final api = _apiWith(
          client: MockClient((request) async {
            if (request.method == 'POST' &&
                request.url.path == '/api/v1/events') {
              capturedBody = request.body;
              return http.Response(jsonEncode({'id': 1, 'name': 'n'}), 201);
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
            .addEvent('My Event', 5, status: 'draft');

        final decoded = jsonDecode(capturedBody!) as Map<String, dynamic>;
        expect(decoded, containsPair('name', 'My Event'));
        expect(decoded, containsPair('creatorId', 5));
        expect(decoded, containsPair('status', 'draft'));
        // The whole point of #215: no snake_case keys leak into the wire body.
        expect(decoded, isNot(contains('creator_id')));
        expect(decoded, isNot(contains('user_id')));
      },
    );

    test(
      'banUser sends camelCase proto3 JSON (bannedUntil, not banned_until)',
      () async {
        String? capturedBody;
        final api = _apiWith(
          client: MockClient((request) async {
            if (request.method == 'POST' && request.url.path.endsWith('/ban')) {
              capturedBody = request.body;
              return http.Response('', 200);
            }
            return http.Response(jsonEncode([]), 200);
          }),
        );
        final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWith((ref) => api)],
        );
        addTearDown(container.dispose);

        await container
            .read(adminControllerProvider.notifier)
            .banUser(2, 1, reason: 'spam', bannedUntil: '2026-12-31T00:00:00Z');

        final decoded = jsonDecode(capturedBody!) as Map<String, dynamic>;
        expect(decoded, containsPair('reason', 'spam'));
        expect(decoded, containsPair('bannedUntil', '2026-12-31T00:00:00Z'));
        expect(decoded, isNot(contains('banned_until')));
      },
    );

    test('addMerch preserves an empty photoUrl on the wire (#215)', () async {
      // photo_url is an `optional string`; setting it to '' must still emit
      // "photoUrl": "" (presence-tracked), matching the old hand-written map
      // and the generateDebugData path that uses '' for icon-less items.
      // If this field ever becomes non-optional, toProto3Json() would omit it
      // and the DB would flip from empty-string to NULL — pin the invariant.
      String? capturedBody;
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' && request.url.path.endsWith('/merch')) {
            capturedBody = request.body;
            return http.Response(jsonEncode({'id': 1}), 201);
          }
          return http.Response(jsonEncode([]), 200);
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await container
          .read(merchControllerProvider.notifier)
          .addMerch(1, 'Photo Card #1', '', 'Photo Cards');

      final decoded = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(decoded, containsPair('name', 'Photo Card #1'));
      expect(decoded, containsPair('photoUrl', ''));
      expect(decoded, containsPair('groupName', 'Photo Cards'));
      expect(decoded, isNot(contains('group_name')));
    });

    test('updateMerch sends name + photoUrl on the wire (#205)', () async {
      // The "Edit Item" dialog lets a creator change an item's image as well
      // as its name. The provider must PUT both fields (camelCase proto3 JSON)
      // and must OMIT groupName when the caller does not supply it, so an
      // edit that only touches name+image does not clobber the group. The
      // userId is always present (required by the backend auth check).
      String? capturedBody;
      String? capturedMethod;
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'PUT' &&
              RegExp(
                r'/api/v1/events/\d+/merch/\d+$',
              ).hasMatch(request.url.path)) {
            capturedMethod = request.method;
            capturedBody = request.body;
            return http.Response(jsonEncode({'id': 1}), 200);
          }
          return http.Response(jsonEncode([]), 200);
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await container
          .read(merchControllerProvider.notifier)
          .updateMerch(
            1,
            7,
            42,
            name: 'Renamed Card',
            photoUrl: 'uploads/abc.png',
          );

      expect(capturedMethod, 'PUT');
      final decoded = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(decoded, containsPair('userId', 42));
      expect(decoded, containsPair('name', 'Renamed Card'));
      expect(decoded, containsPair('photoUrl', 'uploads/abc.png'));
      // groupName was not supplied — it must not be sent (no group clobber).
      expect(decoded, isNot(contains('groupName')));
      expect(decoded, isNot(contains('group_name')));
    });
  });
}
