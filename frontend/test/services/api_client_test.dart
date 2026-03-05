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

    group('Response Handling Boundaries', () {
      test('throws Exception for status code 199 (below 200)', () async {
        final mockClient = MockClient((request) async {
          return http.Response('Information', 199);
        });
        final apiClient = ApiClient(config, client: mockClient);

        expect(
          () async => await apiClient.get('/api/test'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('API Error: 199 Information'),
          )),
        );
      });

      test('returns json for status code 200 (lower bound of success)', () async {
        final mockClient = MockClient((request) async {
          return http.Response(jsonEncode({'message': 'OK'}), 200);
        });
        final apiClient = ApiClient(config, client: mockClient);

        final response = await apiClient.get('/api/test');
        expect(response, {'message': 'OK'});
      });

      test('returns json for status code 299 (upper bound of success)', () async {
        final mockClient = MockClient((request) async {
          return http.Response(jsonEncode({'message': 'OK'}), 299);
        });
        final apiClient = ApiClient(config, client: mockClient);

        final response = await apiClient.get('/api/test');
        expect(response, {'message': 'OK'});
      });

      test('throws Exception for status code 300 (above 299)', () async {
        final mockClient = MockClient((request) async {
          return http.Response('Multiple Choices', 300);
        });
        final apiClient = ApiClient(config, client: mockClient);

        expect(
          () async => await apiClient.get('/api/test'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('API Error: 300 Multiple Choices'),
          )),
        );
      });
    });
  });
}
