import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/providers/auth_provider.dart';
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

  group('isGuestRestoreUuid', () {
    test('accepts standard UUID v4-shaped keys', () {
      expect(
        isGuestRestoreUuid('550e8400-e29b-41d4-a716-446655440000'),
        isTrue,
      );
      expect(
        isGuestRestoreUuid('  550e8400-e29b-41d4-a716-446655440000  '),
        isTrue,
      );
    });

    test('rejects empty, short, or non-uuid strings', () {
      expect(isGuestRestoreUuid(null), isFalse);
      expect(isGuestRestoreUuid(''), isFalse);
      expect(isGuestRestoreUuid('not-a-uuid'), isFalse);
      expect(isGuestRestoreUuid('550e8400e29b41d4a716446655440000'), isFalse);
      expect(isGuestRestoreUuid('guest_user'), isFalse);
    });
  });

  group('parseRestoreUuidFromUri', () {
    test('reads restore_uuid from query', () {
      const id = '550e8400-e29b-41d4-a716-446655440000';
      final uri = Uri.parse('https://ymatch.example/?restore_uuid=$id');
      expect(parseRestoreUuidFromUri(uri), id);
    });

    test('reads restore_uuid from hash fragment query', () {
      const id = '550e8400-e29b-41d4-a716-446655440000';
      final uri = Uri.parse('https://ymatch.example/#/?restore_uuid=$id');
      expect(parseRestoreUuidFromUri(uri), id);
    });

    test('returns null when missing or invalid', () {
      expect(
        parseRestoreUuidFromUri(Uri.parse('https://ymatch.example/')),
        isNull,
      );
      expect(
        parseRestoreUuidFromUri(
          Uri.parse('https://ymatch.example/?restore_uuid=nope'),
        ),
        isNull,
      );
      expect(
        parseRestoreUuidFromUri(
          Uri.parse(
            'https://ymatch.example/?dev_user=550e8400-e29b-41d4-a716-446655440000',
          ),
        ),
        isNull,
      );
    });
  });

  group('parseDevUserFromUri still works via shared helper', () {
    test('reads dev_user from query', () {
      final uri = Uri.parse('https://localhost/?dev_user=tab-alice');
      expect(parseDevUserFromUri(uri), 'tab-alice');
    });
  });

  group('AuthController.checkLogin + restore_uuid (#527)', () {
    const restoreId = '550e8400-e29b-41d4-a716-446655440000';

    http.Response ok(Object body) => http.Response(jsonEncode(body), 200);

    tearDown(() {
      currentAppUri = () => Uri.base;
      enableDevSessionOverrides = true;
    });

    test('restores guest from restore_uuid when prefs are empty', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      enableDevSessionOverrides = false;
      currentAppUri = () =>
          Uri.parse('https://ymatch.example/?restore_uuid=$restoreId');

      var guestCalls = 0;
      String? lastUuid;
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/auth/guest') {
            guestCalls++;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            lastUuid = body['uuid'] as String?;
            return ok({
              'id': 42,
              'username': 'Guest_restored',
              'uuid': lastUuid,
            });
          }
          return ok(<dynamic>[]);
        }),
      );

      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      for (
        var i = 0;
        i < 50 && container.read(authProvider).value == null;
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(guestCalls, 1);
      expect(lastUuid, restoreId);
      expect(container.read(authProvider).value?.uuid, restoreId);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('user_uuid'), restoreId);
    });

    test('ignores invalid restore_uuid and stays logged out', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      enableDevSessionOverrides = false;
      currentAppUri = () =>
          Uri.parse('https://ymatch.example/?restore_uuid=not-valid');

      var guestCalls = 0;
      final api = _apiWith(
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/auth/guest') {
            guestCalls++;
            return ok({'id': 1, 'username': 'x', 'uuid': 'should-not'});
          }
          return ok(<dynamic>[]);
        }),
      );

      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(guestCalls, 0);
      expect(container.read(authProvider).value, isNull);
    });
  });

  group('AuthController.restoreAccount', () {
    const savedId = '0b5c3a2e-4f1d-4c7a-9e8b-1a2b3c4d5e6f';
    const knownId = '550e8400-e29b-41d4-a716-446655440000';
    const unknownId = '7d9f1e2a-3b4c-4d5e-8f60-718293a4b5c6';
    const brokenId = '2e4c6a8b-1d3f-4a5b-9c7d-8e9fa0b1c2d3';

    late List<Map<String, dynamic>> guestBodies;

    ApiClient api() => _apiWith(
      client: MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/auth/guest') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          guestBodies.add(body);
          final uuid = body['uuid'] as String;
          if (uuid == unknownId) {
            return http.Response('{"error":"Account not found"}', 404);
          }
          if (uuid == brokenId) {
            return http.Response('{"error":"Internal"}', 500);
          }
          return http.Response(
            jsonEncode({'id': uuid == savedId ? 1 : 2, 'uuid': uuid}),
            200,
          );
        }
        return http.Response('[]', 200);
      }),
    );

    Future<ProviderContainer> loggedInAsSaved() async {
      SharedPreferences.setMockInitialValues({'user_uuid': savedId});
      enableDevSessionOverrides = false;
      currentAppUri = () => Uri.parse('https://ymatch.example/');
      guestBodies = [];
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api())],
      );
      addTearDown(container.dispose);
      container.read(authProvider);
      for (
        var i = 0;
        i < 50 && container.read(authProvider).value == null;
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(container.read(authProvider).value?.uuid, savedId);
      return container;
    }

    tearDown(() {
      currentAppUri = () => Uri.base;
      enableDevSessionOverrides = true;
    });

    test('unknown key keeps the saved key and reports failure', () async {
      final container = await loggedInAsSaved();

      await container.read(authProvider.notifier).restoreAccount(unknownId);

      expect(guestBodies.last['existingOnly'], isTrue);
      expect(
        container.read(authProvider).error,
        isA<AccountRestoreException>(),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('user_uuid'), savedId);
    });

    test('server error is not reported as a bad key', () async {
      final container = await loggedInAsSaved();

      await container.read(authProvider.notifier).restoreAccount(brokenId);

      final error = container.read(authProvider).error;
      expect(error, isNotNull);
      expect(error, isNot(isA<AccountRestoreException>()));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('user_uuid'), savedId);
    });

    test('known key logs in and replaces the saved key', () async {
      final container = await loggedInAsSaved();

      await container.read(authProvider.notifier).restoreAccount(knownId);

      expect(guestBodies.last['existingOnly'], isTrue);
      expect(container.read(authProvider).value?.uuid, knownId);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('user_uuid'), knownId);
    });

    test('unknown restore_uuid falls back to the saved account', () async {
      SharedPreferences.setMockInitialValues({'user_uuid': savedId});
      enableDevSessionOverrides = false;
      currentAppUri = () =>
          Uri.parse('https://ymatch.example/?restore_uuid=$unknownId');
      guestBodies = [];
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api())],
      );
      addTearDown(container.dispose);
      container.read(authProvider);
      for (
        var i = 0;
        i < 50 && container.read(authProvider).value == null;
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(guestBodies.map((b) => b['uuid']), [unknownId, savedId]);
      expect(container.read(authProvider).value?.uuid, savedId);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('user_uuid'), savedId);
    });
  });
}
