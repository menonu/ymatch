import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';

const _uuid = '550e8400-e29b-41d4-a716-446655440000';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    enableDevSessionOverrides = false;
    currentAppUri = () => Uri.parse('https://ymatch.example/');
  });
  tearDown(() {
    currentAppUri = () => Uri.base;
    enableDevSessionOverrides = true;
  });

  test(
    'updateUsername keeps the session uuid/deviceToken the server omits',
    () async {
      final config = ConfigService()
        ..setBaseUrlForTest('http://localhost:3000');
      final api = ApiClient(
        config,
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/guest') {
            return http.Response(
              jsonEncode({
                'id': 7,
                'username': 'Guest_x',
                'uuid': _uuid,
                'deviceToken': 'push-token',
              }),
              200,
            );
          }
          if (request.url.path == '/api/v1/users/7') {
            // The server returns neither `uuid` nor `deviceToken` here.
            return http.Response(
              jsonEncode({'id': 7, 'username': 'renamed'}),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWith((ref) => api)],
      );
      addTearDown(container.dispose);

      final auth = container.read(authProvider.notifier);
      await auth.restoreAccount(_uuid);
      await auth.updateUsername(7, 'renamed');

      final user = container.read(authProvider).value!;
      expect(user.username, 'renamed');
      expect(user.uuid, _uuid);
      expect(user.deviceToken, 'push-token');
    },
  );
}
