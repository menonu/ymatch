import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Why a location or geocoding operation failed.
enum LocationErrorKind {
  permissionDenied,
  serviceDisabled,
  unavailable,
  searchFailed,
}

/// Typed failure for GPS / place-search flows.
class LocationException implements Exception {
  const LocationException(this.kind, [this.details]);

  final LocationErrorKind kind;
  final String? details;

  @override
  String toString() =>
      'LocationException($kind${details != null ? ': $details' : ''})';
}

/// A single place result from geocoding (display name + coordinates).
class PlaceSuggestion {
  const PlaceSuggestion({required this.displayName, required this.location});

  final String displayName;
  final LatLng location;
}

/// Abstraction over device GPS and place search so UI can be tested with fakes.
abstract class LocationService {
  /// Current device position (requests permission when needed).
  Future<LatLng> getCurrentPosition();

  /// Geocode [query] into place suggestions (empty list when nothing matches).
  Future<List<PlaceSuggestion>> searchPlaces(String query);
}

/// Production [LocationService]: `geolocator` + OpenStreetMap Nominatim.
///
/// Nominatim is used to stay free/keyless and consistent with OSM map tiles.
/// Requires a valid User-Agent per Nominatim usage policy.
class DefaultLocationService implements LocationService {
  DefaultLocationService({
    http.Client? httpClient,
    this.userAgent =
        'ymatch/1.0 (merchandise trade; https://github.com/menonu/ymatch)',
    this.acceptLanguage = 'en',
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final String userAgent;
  final String acceptLanguage;

  /// Tokyo city-hall area — same default as the original map picker.
  static const LatLng defaultCenter = LatLng(35.6895, 139.6917);

  @override
  Future<LatLng> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(LocationErrorKind.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationException(LocationErrorKind.permissionDenied);
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } on LocationException {
      rethrow;
    } catch (e) {
      throw LocationException(LocationErrorKind.unavailable, e.toString());
    }
  }

  @override
  Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': trimmed,
      'format': 'json',
      'limit': '5',
    });

    try {
      final response = await _httpClient.get(
        uri,
        headers: {'User-Agent': userAgent, 'Accept-Language': acceptLanguage},
      );

      if (response.statusCode != 200) {
        throw LocationException(
          LocationErrorKind.searchFailed,
          'HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const LocationException(LocationErrorKind.searchFailed);
      }

      final results = <PlaceSuggestion>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final name = item['display_name'];
        final lat = item['lat'];
        final lon = item['lon'];
        if (name is! String || lat == null || lon == null) continue;
        final latD = double.tryParse(lat.toString());
        final lonD = double.tryParse(lon.toString());
        if (latD == null || lonD == null) continue;
        results.add(
          PlaceSuggestion(displayName: name, location: LatLng(latD, lonD)),
        );
      }
      return results;
    } on LocationException {
      rethrow;
    } catch (e) {
      throw LocationException(LocationErrorKind.searchFailed, e.toString());
    }
  }
}
