import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:frontend/services/web_push_platform.dart';
import 'package:frontend/services/web_push_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakePlatform implements WebPushPlatform {
  _FakePlatform({this.permission = 'default', this.subscription});

  String permission;
  BrowserPushSubscription? subscription;
  bool subscribed = false;
  bool unsubscribed = false;

  @override
  bool get isSupported => true;

  @override
  Future<String> permissionState() async => permission;

  @override
  Future<void> ensureServiceWorker() async {}

  @override
  Future<BrowserPushSubscription?> currentSubscription() async => subscription;

  @override
  Future<BrowserPushSubscription> subscribe(String vapidPublicKey) async {
    subscribed = true;
    permission = 'granted';
    subscription = const BrowserPushSubscription(
      endpoint: 'https://push.example/ep',
      p256dh: 'p256',
      auth: 'auth',
    );
    return subscription!;
  }

  @override
  Future<void> unsubscribe() async {
    unsubscribed = true;
    subscription = null;
  }
}

void main() {
  group('decodeVapidPublicKey', () {
    test('decodes url-safe base64 without padding', () {
      // "hello" as url-safe base64
      final bytes = decodeVapidPublicKey('aGVsbG8');
      expect(utf8.decode(bytes), 'hello');
    });
  });

  group('WebPushService', () {
    test('fetchVapidPublicKey returns null on 404', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/api/v1/push/vapid-public-key');
        return http.Response('not found', 404);
      });
      final config = ConfigService()..setBaseUrlForTest('http://test');
      final service = WebPushService(
        client: ApiClient(config, client: mock),
        platformImpl: _FakePlatform(),
      );
      expect(await service.fetchVapidPublicKey(), isNull);
    });

    test('fetchVapidPublicKey returns publicKey', () async {
      final mock = MockClient((request) async {
        return http.Response(jsonEncode({'publicKey': 'BK_test_key'}), 200);
      });
      final config = ConfigService()..setBaseUrlForTest('http://test');
      final service = WebPushService(
        client: ApiClient(config, client: mock),
        platformImpl: _FakePlatform(),
      );
      expect(await service.fetchVapidPublicKey(), 'BK_test_key');
    });

    test('enable unsubscribes browser when persist fails', () async {
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('/vapid-public-key')) {
          return http.Response(jsonEncode({'publicKey': 'BKxx'}), 200);
        }
        if (request.method == 'PUT') {
          return http.Response('fail', 500);
        }
        return http.Response('unexpected', 500);
      });
      final platform = _FakePlatform();
      final config = ConfigService()..setBaseUrlForTest('http://test');
      final service = WebPushService(
        client: ApiClient(config, client: mock),
        platformImpl: platform,
      );

      await expectLater(service.enable(7), throwsA(isA<Exception>()));
      expect(platform.subscribed, isTrue);
      expect(platform.unsubscribed, isTrue);
    });

    test('enable persists subscription after subscribe', () async {
      final requests = <http.BaseRequest>[];
      final mock = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/vapid-public-key')) {
          return http.Response(jsonEncode({'publicKey': 'BKxx'}), 200);
        }
        if (request.method == 'PUT') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['endpoint'], 'https://push.example/ep');
          expect(body['keys']['p256dh'], 'p256');
          return http.Response(
            jsonEncode({'id': 1, 'userId': 7, 'endpoint': body['endpoint']}),
            200,
          );
        }
        return http.Response('unexpected', 500);
      });
      final platform = _FakePlatform();
      final config = ConfigService()..setBaseUrlForTest('http://test');
      final service = WebPushService(
        client: ApiClient(config, client: mock),
        platformImpl: platform,
      );

      final sub = await service.enable(7);
      expect(platform.subscribed, isTrue);
      expect(sub.endpoint, 'https://push.example/ep');
      expect(requests.any((r) => r.method == 'PUT'), isTrue);
    });

    test('disable unsubscribes and deletes endpoint', () async {
      final methods = <String>[];
      final mock = MockClient((request) async {
        methods.add(request.method);
        if (request.method == 'DELETE') {
          expect(request.url.path, '/api/v1/push/subscriptions');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['endpoint'], 'https://push.example/ep');
          return http.Response(jsonEncode({'deleted': true}), 200);
        }
        return http.Response('{}', 200);
      });
      final platform = _FakePlatform(
        permission: 'granted',
        subscription: const BrowserPushSubscription(
          endpoint: 'https://push.example/ep',
          p256dh: 'p',
          auth: 'a',
        ),
      );
      final config = ConfigService()..setBaseUrlForTest('http://test');
      final service = WebPushService(
        client: ApiClient(config, client: mock),
        platformImpl: platform,
      );

      await service.disable(3);
      expect(platform.unsubscribed, isTrue);
      expect(methods, contains('DELETE'));
    });
  });
}
