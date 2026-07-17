import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/location_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('DefaultLocationService.searchPlaces', () {
    test('parses Nominatim JSON into PlaceSuggestion list', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'nominatim.openstreetmap.org');
        expect(request.url.path, '/search');
        expect(request.url.queryParameters['q'], 'Tokyo Station');
        expect(request.headers['User-Agent'], contains('ymatch'));
        return http.Response(
          jsonEncode([
            {
              'display_name': 'Tokyo Station, Japan',
              'lat': '35.6812',
              'lon': '139.7671',
            },
            {
              'display_name': 'Missing coords should be skipped',
              'lat': null,
              'lon': null,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = DefaultLocationService(httpClient: client);
      final results = await service.searchPlaces('Tokyo Station');

      expect(results, hasLength(1));
      expect(results.first.displayName, 'Tokyo Station, Japan');
      expect(results.first.location.latitude, closeTo(35.6812, 0.0001));
      expect(results.first.location.longitude, closeTo(139.7671, 0.0001));
    });

    test(
      'returns empty list for blank query without calling network',
      () async {
        var called = false;
        final client = MockClient((request) async {
          called = true;
          return http.Response('[]', 200);
        });

        final service = DefaultLocationService(httpClient: client);
        final results = await service.searchPlaces('   ');

        expect(results, isEmpty);
        expect(called, isFalse);
      },
    );

    test('throws LocationException on non-200', () async {
      final client = MockClient((request) async => http.Response('error', 503));
      final service = DefaultLocationService(httpClient: client);

      await expectLater(
        service.searchPlaces('Osaka'),
        throwsA(
          isA<LocationException>().having(
            (e) => e.kind,
            'kind',
            LocationErrorKind.searchFailed,
          ),
        ),
      );
    });
  });
}
