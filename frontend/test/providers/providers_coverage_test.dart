// Coverage tests for the Riverpod providers in lib/providers/providers.dart.
//
// Part of #185 Phase 2 (gap 4 — provider tests). The companion file
// providers_test.dart pins the #239 contracts (UserInventoryNotifier.updateItem
// rethrow + EventsController fire-and-forget toggles); this file covers the
// rest: every provider/controller gets at least one test, with extra tests
// for the ones carrying real logic (eventsProvider sort, MerchController.addMerch
// rethrow per #227, AuthController state transitions, AdminController, and the
// error-swallowing backend status/health providers).
//
// Pattern mirrors providers_test.dart: a real ApiClient over a `MockClient`
// (package:http/testing.dart), a ProviderContainer with apiClientProvider
// overridden, no ProviderScope. No new dev-dependencies.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/models/models.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';

/// Build a real `ApiClient` whose HTTP layer is the given mock `client`.
ApiClient _apiWith({required http.Client client}) {
  final config = ConfigService();
  config.setBaseUrlForTest('http://localhost:3000');
  return ApiClient(config, client: client);
}

/// A 200 JSON response.
http.Response _ok(Object body) => http.Response(jsonEncode(body), 200);

/// A 200 response with an empty body (ApiClient maps this to `{}`).
http.Response _okEmpty() => http.Response('', 200);

/// A protobuf message built from proto3 JSON.
T _proto<T>(Map<String, dynamic> json, T Function() factory) {
  final msg = factory();
  // The generated message classes expose mergeFromProto3Json.
  (msg as dynamic).mergeFromProto3Json(json);
  return msg;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Several providers watch currentUserProvider -> authProvider, whose
  // AuthController constructor auto-runs checkLogin() (reads SharedPreferences).
  // Mock empty prefs so no guest session is attempted during tests.
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // ---- AuthController / authProvider / currentUserProvider ----

  group('AuthController', () {
    test('login sets state to the returned user', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/auth/login') {
            return _ok({'id': 1, 'username': 'alice', 'uuid': 'u-1'});
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).login('alice', 'pw');

      final state = container.read(authProvider);
      expect(state.hasError, isFalse);
      expect(state.value?.id, 1);
      expect(state.value?.username, 'alice');
      // currentUserProvider derives from authProvider.
      expect(container.read(currentUserProvider)?.id, 1);
    });

    test('login failure sets state to error', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/auth/login') {
            return http.Response('Bad Request', 400);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).login('alice', 'wrong');

      expect(container.read(authProvider).hasError, isTrue);
    });

    test('logout clears state to null', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/auth/login') {
            return _ok({'id': 1, 'username': 'alice', 'uuid': 'u-1'});
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      // login first to populate state, then logout.
      await container.read(authProvider.notifier).login('alice', 'pw');
      expect(container.read(authProvider).value?.id, 1);

      // logout() is `void ... async` (fire-and-forget); pump the microtask
      // queue until its body has cleared the state.
      container.read(authProvider.notifier).logout();
      for (var i = 0; i < 50 && container.read(authProvider).value != null; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(container.read(authProvider).value, isNull);
    });

    test('updateUsername updates state with the returned user', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'PUT' && request.url.path == '/api/v1/users/1') {
            return _ok({'id': 1, 'username': 'alice2', 'uuid': 'u-1'});
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).updateUsername(1, 'alice2');

      expect(container.read(authProvider).value?.username, 'alice2');
    });
  });

  // ---- eventsProvider (sort: favorites first, then id desc) ----

  group('eventsProvider', () {
    test('sorts favorites first then by id descending', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'GET' && request.url.path == '/api/v1/events') {
            return _ok([
              {'id': 1, 'name': 'A', 'isFavorite': false},
              {'id': 3, 'name': 'B', 'isFavorite': true},
              {'id': 2, 'name': 'C', 'isFavorite': true},
            ]);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final events = await container.read(eventsProvider.future);
      expect(events.map((e) => e.id).toList(), [3, 2, 1]);
    });
  });

  // ---- favoriteGroupsProvider ----

  group('favoriteGroupsProvider', () {
    test('returns an empty list when there is no current user', () async {
      final api = _apiWith(client: MockClient((_) async => _ok(<Object>[])));
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      // No login -> currentUserProvider is null.
      final groups = await container.read(favoriteGroupsProvider.future);
      expect(groups, isEmpty);
    });

    test('fetches groups for the current user', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/user/7/favorite_groups') {
            return _ok([
              {'user_id': 7, 'event_id': 1, 'group_name': 'G1'},
              {'user_id': 7, 'event_id': 2, 'group_name': 'G2'},
            ]);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWith((ref) => api),
          currentUserProvider.overrideWithValue(
            _proto<User>({'id': 7, 'username': 'bob'}, User.new),
          ),
        ],
      );
      addTearDown(container.dispose);

      final groups = await container.read(favoriteGroupsProvider.future);
      expect(groups.length, 2);
      expect(groups.first.groupName, 'G1');
    });
  });

  // ---- merchProvider (family by eventId) ----

  group('merchProvider', () {
    test('fetches merch for the event', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/events/5/merch') {
            return _ok([
              {'id': 1, 'name': 'Card A'},
              {'id': 2, 'name': 'Card B'},
            ]);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final merch = await container.read(merchProvider(5).future);
      expect(merch.length, 2);
      expect(merch.first.name, 'Card A');
    });
  });

  // ---- EventsController (addEvent, registerView) ----

  group('EventsController', () {
    test('addEvent succeeds -> state data', () async {
      var postCalls = 0;
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' && request.url.path == '/api/v1/events') {
            postCalls++;
            return _ok({'id': 1, 'name': 'Fest'});
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await container
          .read(eventsControllerProvider.notifier)
          .addEvent('Fest', 1);

      // The controller starts and ends in AsyncData(null), so hasError alone
      // would pass even for a no-op body. Assert the endpoint was actually hit.
      expect(postCalls, 1);
      expect(container.read(eventsControllerProvider).hasError, isFalse);
    });

    test('addEvent failure -> state error AND rethrows (#266)', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' && request.url.path == '/api/v1/events') {
            return http.Response('Conflict', 409);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      // #266: callers (create-event dialog) need the failure visible so they
      // can show a SnackBar instead of closing as if create succeeded.
      await expectLater(
        container.read(eventsControllerProvider.notifier).addEvent('Fest', 1),
        throwsA(isA<Exception>()),
      );

      expect(container.read(eventsControllerProvider).hasError, isTrue);
    });

    test('registerView is fire-and-forget (no throw on failure)', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' && request.url.path == '/api/v1/events/1/view') {
            return http.Response('Internal Server Error', 500);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      // Completes without throwing.
      await container
          .read(eventsControllerProvider.notifier)
          .registerView(1, 1);
    });

    test('updateEvent failure -> state error AND rethrows (#395)', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'PUT' &&
              request.url.path == '/api/v1/events/3') {
            return http.Response('Conflict', 409);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(eventsControllerProvider.notifier)
            .updateEvent(3, 1, 'Renamed'),
        throwsA(isA<Exception>()),
      );
      expect(container.read(eventsControllerProvider).hasError, isTrue);
    });

    test(
      'deleteEventByCreator failure -> state error AND rethrows (#395)',
      () async {
        final api = _apiWith(
          client: MockClient((request) async {
            if (request.method == 'DELETE' &&
                request.url.path == '/api/v1/admin/events/3') {
              return http.Response('Forbidden', 403);
            }
            return _okEmpty();
          }),
        );
        final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWith((ref) => api)],
        );
        addTearDown(container.dispose);

        await expectLater(
          container
              .read(eventsControllerProvider.notifier)
              .deleteEventByCreator(3, 1),
          throwsA(isA<Exception>()),
        );
        expect(container.read(eventsControllerProvider).hasError, isTrue);
      },
    );

    test(
      'generateDebugData failure -> state error AND rethrows (#395)',
      () async {
        final api = _apiWith(
          client: MockClient((request) async {
            // First step of generateDebugData is POST /api/v1/events.
            if (request.method == 'POST' &&
                request.url.path == '/api/v1/events') {
              return http.Response('Internal Server Error', 500);
            }
            return _okEmpty();
          }),
        );
        final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWith((ref) => api)],
        );
        addTearDown(container.dispose);

        await expectLater(
          container
              .read(eventsControllerProvider.notifier)
              .generateDebugData(1),
          throwsA(isA<Exception>()),
        );
        expect(container.read(eventsControllerProvider).hasError, isTrue);
      },
    );
  });

  // ---- MerchController (addMerch rethrows per #227) ----

  group('MerchController', () {
    test('addMerch succeeds -> state data', () async {
      var postCalls = 0;
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/events/1/merch') {
            postCalls++;
            return _ok({'id': 9, 'name': 'Card'});
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await container
          .read(merchControllerProvider.notifier)
          .addMerch(1, 'Card', 'http://img');

      // Controller starts/ends in AsyncData(null); assert the POST happened.
      expect(postCalls, 1);
      expect(container.read(merchControllerProvider).hasError, isFalse);
    });

    test('addMerch failure -> state error AND rethrows (#227)', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/events/1/merch') {
            return http.Response('Unprocessable Entity', 422);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      // #227: the 422 must be visible to the caller so the screen shows a
      // real error instead of a misleading "Added successfully" SnackBar.
      await expectLater(
        container
            .read(merchControllerProvider.notifier)
            .addMerch(1, 'Card', 'http://img'),
        throwsA(isA<Exception>()),
      );
      expect(container.read(merchControllerProvider).hasError, isTrue);
    });

    test(
      'deleteMerchByCreator failure -> state error AND rethrows (#395)',
      () async {
        final api = _apiWith(
          client: MockClient((request) async {
            if (request.method == 'DELETE' &&
                request.url.path == '/api/v1/events/1/merch/9') {
              return http.Response('Forbidden', 403);
            }
            return _okEmpty();
          }),
        );
        final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWith((ref) => api)],
        );
        addTearDown(container.dispose);

        await expectLater(
          container
              .read(merchControllerProvider.notifier)
              .deleteMerchByCreator(1, 9, 1),
          throwsA(isA<Exception>()),
        );
        expect(container.read(merchControllerProvider).hasError, isTrue);
      },
    );
  });

  // ---- Admin read providers ----

  group('admin read providers', () {
    test('adminMerchProvider fetches merch', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'GET' && request.url.path == '/api/v1/admin/merch') {
            return _ok([
              {'id': 1, 'name': 'M1'},
            ]);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final merch = await container.read(adminMerchProvider.future);
      expect(merch.length, 1);
    });

    test('adminGroupsProvider fetches groups', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/admin/groups') {
            return _ok([
              {
                'eventId': 42,
                'eventName': 'Test Event',
                'groupName': 'test-group',
                'itemCount': 3,
              },
            ]);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final groups = await container.read(adminGroupsProvider.future);
      expect(groups.length, 1);
      expect(groups.first.eventId, 42);
      expect(groups.first.eventName, 'Test Event');
      expect(groups.first.groupName, 'test-group');
      expect(groups.first.itemCount, 3);
    });

    test('adminMatchesProvider fetches matches', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/admin/matches') {
            return _ok([
              {'id': 1, 'status': 'PENDING'},
            ]);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final matches = await container.read(adminMatchesProvider.future);
      expect(matches.length, 1);
    });

    test('adminUsersProvider fetches users', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'GET' && request.url.path == '/api/v1/users') {
            return _ok([
              {'id': 1, 'username': 'alice'},
            ]);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final users = await container.read(adminUsersProvider.future);
      expect(users.length, 1);
      expect(users.first.username, 'alice');
    });
  });

  // ---- AdminController ----

  group('AdminController', () {
    test('banUser succeeds -> state data', () async {
      var postCalls = 0;
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/admin/users/5/ban') {
            postCalls++;
            return _okEmpty();
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await container
          .read(adminControllerProvider.notifier)
          .banUser(5, 1, reason: 'spam');

      // Controller starts/ends in AsyncData(null); assert the POST happened.
      expect(postCalls, 1);
      expect(container.read(adminControllerProvider).hasError, isFalse);
    });

    test('banUser failure -> state error AND rethrows (#266)', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/admin/users/5/ban') {
            return http.Response('Forbidden', 403);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(adminControllerProvider.notifier)
            .banUser(5, 1, reason: 'spam'),
        throwsA(isA<Exception>()),
      );

      expect(container.read(adminControllerProvider).hasError, isTrue);
    });

    test('unbanUser failure -> state error AND rethrows (#395)', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/admin/users/5/unban') {
            return http.Response('Forbidden', 403);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(adminControllerProvider.notifier)
            .unbanUser(5, 1),
        throwsA(isA<Exception>()),
      );
      expect(container.read(adminControllerProvider).hasError, isTrue);
    });

    test(
      'updateUserRole failure -> state error AND rethrows (#395)',
      () async {
        final api = _apiWith(
          client: MockClient((request) async {
            if (request.method == 'POST' &&
                request.url.path == '/api/v1/admin/users/5/role') {
              return http.Response('Forbidden', 403);
            }
            return _okEmpty();
          }),
        );
        final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWith((ref) => api)],
        );
        addTearDown(container.dispose);

        await expectLater(
          container
              .read(adminControllerProvider.notifier)
              .updateUserRole(5, 1, 'moderator'),
          throwsA(isA<Exception>()),
        );
        expect(container.read(adminControllerProvider).hasError, isTrue);
      },
    );

    test('publishEvent failure -> state error AND rethrows (#395)', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/events/3/publish') {
            return http.Response('Forbidden', 403);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(adminControllerProvider.notifier)
            .publishEvent(3, 1),
        throwsA(isA<Exception>()),
      );
      expect(container.read(adminControllerProvider).hasError, isTrue);
    });

    test('publishMerch failure -> state error AND rethrows (#395)', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/events/1/merch/9/publish') {
            return http.Response('Forbidden', 403);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(adminControllerProvider.notifier)
            .publishMerch(1, 9, 1),
        throwsA(isA<Exception>()),
      );
      expect(container.read(adminControllerProvider).hasError, isTrue);
    });

    test('deleteEvent failure -> state error AND rethrows (#395)', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'DELETE' &&
              request.url.path == '/api/v1/admin/events/3') {
            return http.Response('Forbidden', 403);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(adminControllerProvider.notifier)
            .deleteEvent(3, 1),
        throwsA(isA<Exception>()),
      );
      expect(container.read(adminControllerProvider).hasError, isTrue);
    });

    test('deleteMerch failure -> state error AND rethrows (#395)', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'DELETE' &&
              request.url.path == '/api/v1/admin/merch/9') {
            return http.Response('Forbidden', 403);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(adminControllerProvider.notifier)
            .deleteMerch(9, 1),
        throwsA(isA<Exception>()),
      );
      expect(container.read(adminControllerProvider).hasError, isTrue);
    });

    test('deleteMatch failure -> state error AND rethrows (#395)', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'DELETE' &&
              request.url.path == '/api/v1/admin/matches/4') {
            return http.Response('Forbidden', 403);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(adminControllerProvider.notifier)
            .deleteMatch(4, 1),
        throwsA(isA<Exception>()),
      );
      expect(container.read(adminControllerProvider).hasError, isTrue);
    });
  });

  // ---- matchesProvider + notificationCountsProvider (family by userId) ----

  group('matchesProvider', () {
    test('fetches matches for the user', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/matches/user/7') {
            return _ok([
              {'id': 1, 'status': 'PENDING'},
              {'id': 2, 'status': 'OFFERED'},
            ]);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final matches = await container.read(matchesProvider(7).future);
      expect(matches.length, 2);
    });
  });

  group('notificationCountsProvider', () {
    test('fetches counts for the user', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/matches/user/7/counts') {
            return _ok(<String, Object>{
              'pendingMatches': 3,
              'total': 5,
            });
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final counts = await container.read(notificationCountsProvider(7).future);
      // Assert a real field so the merge is actually constrained (not just
      // "an instance was returned").
      expect(counts.pendingMatches, 3);
      expect(counts.total, 5);
    });
  });

  // ---- MatchController (#241) ----

  group('MatchController', () {
    test('submitOffer POSTs OfferTradeRequest proto body and clears error',
        () async {
      String? capturedBody;
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/matches/9/offer') {
            capturedBody = request.body;
            return _okEmpty();
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final item = OfferItem()
        ..merchId = 1
        ..giverUserId = 7
        ..quantity = 1;
      await container
          .read(matchControllerProvider.notifier)
          .submitOffer(7, 9, [item]);

      expect(container.read(matchControllerProvider).hasError, isFalse);
      expect(capturedBody, isNotNull);
      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(body['userId'], 7);
      expect(body['items'], isA<List>());
      expect((body['items'] as List).first['merchId'], 1);
    });

    test('updateStatus POSTs UpdateMatchStatusRequest proto body', () async {
      String? capturedBody;
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/matches/9/status') {
            capturedBody = request.body;
            return _okEmpty();
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await container
          .read(matchControllerProvider.notifier)
          .updateStatus(7, 9, 'ACCEPTED');

      expect(container.read(matchControllerProvider).hasError, isFalse);
      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(body['status'], 'ACCEPTED');
      expect(body['userId'], 7);
    });

    test('applyInventory POSTs ApplyInventoryRequest proto body', () async {
      String? capturedBody;
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/matches/9/apply-inventory') {
            capturedBody = request.body;
            return _okEmpty();
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await container
          .read(matchControllerProvider.notifier)
          .applyInventory(7, 9);

      expect(container.read(matchControllerProvider).hasError, isFalse);
      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(body['userId'], 7);
      // Default false is omitted by proto3 JSON (or emitted as false).
      expect(body['skipHaveDecrement'] ?? false, isFalse);
    });

    test('applyInventory sends skipHaveDecrement when true', () async {
      String? capturedBody;
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/matches/9/apply-inventory') {
            capturedBody = request.body;
            return _okEmpty();
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      await container
          .read(matchControllerProvider.notifier)
          .applyInventory(7, 9, skipHaveDecrement: true);

      expect(container.read(matchControllerProvider).hasError, isFalse);
      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(body['userId'], 7);
      expect(body['skipHaveDecrement'], isTrue);
    });

    test('mutation failure sets error state (no rethrow)', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/matches/9/status') {
            return http.Response('bad status', 422);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      // Completes without throwing — screen listens on state for SnackBars.
      await container
          .read(matchControllerProvider.notifier)
          .updateStatus(7, 9, 'ACCEPTED');

      expect(container.read(matchControllerProvider).hasError, isTrue);
    });
  });

  // ---- ChatController / messagesProvider (#245) ----

  group('ChatController', () {
    test('sendMessage POSTs SendMessageRequest proto body and invalidates',
        () async {
      String? capturedBody;
      var getCount = 0;
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/matches/9/messages') {
            capturedBody = request.body;
            return _okEmpty();
          }
          // Invalidation re-fetches messages after a successful send.
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/matches/9/messages') {
            getCount++;
            return _ok([]);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      // Keep messagesProvider alive so invalidate re-runs the future
      // (autoDispose would otherwise drop it between reads).
      final sub = container.listen(messagesProvider(9), (_, __) {});
      addTearDown(sub.close);
      await container.read(messagesProvider(9).future);
      expect(getCount, 1);

      await container
          .read(chatControllerProvider.notifier)
          .sendMessage(9, 7, 'hello');

      expect(container.read(chatControllerProvider).hasError, isFalse);
      expect(capturedBody, isNotNull);
      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(body['matchId'], 9);
      expect(body['senderId'], 7);
      expect(body['content'], 'hello');

      // Wait for the post-invalidate re-fetch kicked off by the listener.
      await container.read(messagesProvider(9).future);
      expect(getCount, greaterThanOrEqualTo(2),
          reason: 'sendMessage should invalidate messagesProvider');
    });

    test('sendMessage failure sets error state (no rethrow, no invalidate)',
        () async {
      var getCount = 0;
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/matches/9/messages') {
            return http.Response('bad message', 422);
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/matches/9/messages') {
            getCount++;
            return _ok([]);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final sub = container.listen(messagesProvider(9), (_, __) {});
      addTearDown(sub.close);
      await container.read(messagesProvider(9).future);
      expect(getCount, 1);

      // Completes without throwing — screen listens on state for SnackBars.
      await container
          .read(chatControllerProvider.notifier)
          .sendMessage(9, 7, 'hello');

      expect(container.read(chatControllerProvider).hasError, isTrue);
      // Failure path must not invalidate.
      await container.read(messagesProvider(9).future);
      expect(getCount, 1,
          reason: 'failed send must not invalidate messagesProvider');
    });
  });

  group('messagesProvider', () {
    test('GETs /matches/{id}/messages and maps to Message list', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/matches/9/messages') {
            return _ok([
              {
                'id': 1,
                'matchId': 9,
                'senderId': 7,
                'content': 'hi',
              },
            ]);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final messages = await container.read(messagesProvider(9).future);
      expect(messages, hasLength(1));
      expect(messages.first.senderId, 7);
      expect(messages.first.content, 'hi');
    });
  });

  // ---- searchProvider / searchQueryProvider ----

  group('searchProvider', () {
    test('returns an empty list when the query is blank', () async {
      final api = _apiWith(client: MockClient((_) async => _ok(<Object>[])));
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final results = await container.read(searchProvider.future);
      expect(results, isEmpty);
    });

    test('fetches results for a non-blank query', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/search' &&
              request.url.query == 'q=card') {
            return _ok([
              {'type': 'item', 'id': 1, 'title': 'Card A', 'event_id': 5},
            ]);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      // searchProvider watches searchQueryProvider.
      container.read(searchQueryProvider.notifier).state = 'card';
      final results = await container.read(searchProvider.future);
      expect(results.length, 1);
      expect(results.first.title, 'Card A');
    });
  });

  // ---- backendSystemStatusProvider (swallows errors) ----

  group('backendSystemStatusProvider', () {
    test('returns the status map on success', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/system/status') {
            return _ok(<String, dynamic>{
              'backend_version': '1.2.3',
              'resources': <String, dynamic>{'cpu': 50},
            });
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final status = await container.read(backendSystemStatusProvider.future);
      expect(status['backend_version'], '1.2.3');
    });

    test('swallows fetch errors and returns an error marker', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/system/status') {
            return http.Response('Internal Server Error', 500);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      // Provider catches the exception and returns an error-shaped map
      // rather than propagating AsyncValue.error.
      final status = await container.read(backendSystemStatusProvider.future);
      expect(status['backend_version'], 'error');
      expect(status['resources'], isNull);
    });
  });

  // ---- backendHealthProvider ----

  group('backendHealthProvider', () {
    test('is healthy when the backend responds 200', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'GET' && request.url.path == '/api/v1/events') {
            return _okEmpty();
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      expect(await container.read(backendHealthProvider.future), isTrue);
    });

    test('is unhealthy when the backend is unavailable (503)', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'GET' && request.url.path == '/api/v1/events') {
            return http.Response('Service Unavailable', 503);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      expect(await container.read(backendHealthProvider.future), isFalse);
    });

    test('is healthy when the backend responds a non-connection error (401)', () async {
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'GET' && request.url.path == '/api/v1/events') {
            return http.Response('Unauthorized', 401);
          }
          return _okEmpty();
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      // 401 means the backend is reachable (just rejecting the request).
      expect(await container.read(backendHealthProvider.future), isTrue);
    });
  });
}