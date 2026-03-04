import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';

void main() {
  late ConfigService config;

  setUp(() {
    config = ConfigService();
  });

  group('ApiClient', () {
    test('get() returns decoded json on success', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/test') {
          return http.Response(jsonEncode({'message': 'success'}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(config, client: mockClient);

      final response = await apiClient.get('/api/test');
      expect(response, {'message': 'success'});
    });

    test('get() throws exception on failure', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final apiClient = ApiClient(config, client: mockClient);

      expect(
        () async => await apiClient.get('/api/test'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('API Error: 500'),
        )),
      );
    });

    test('post() returns decoded json on success', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/test' &&
            request.method == 'POST' &&
            request.body == jsonEncode({'key': 'value'})) {
          return http.Response(jsonEncode({'success': true}), 201);
        }
        return http.Response('Bad Request', 400);
      });

      final apiClient = ApiClient(config, client: mockClient);

      final response = await apiClient.post('/api/test', {'key': 'value'});
      expect(response, {'success': true});
    });

    test('post() throws exception on failure', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Bad Request', 400);
      });

      final apiClient = ApiClient(config, client: mockClient);

      expect(
        () async => await apiClient.post('/api/test', {'key': 'value'}),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('API Error: 400'),
        )),
      );
    });
  });
}
