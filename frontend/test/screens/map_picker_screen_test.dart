import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/screens/map_picker_screen.dart';
import 'package:frontend/services/location_service.dart';
import 'package:latlong2/latlong.dart';

/// Controllable fake for GPS + place search.
class _FakeLocationService implements LocationService {
  _FakeLocationService({
    this.position,
    this.positionError,
    this.searchResults = const [],
    this.searchError,
  });

  LatLng? position;
  LocationException? positionError;
  List<PlaceSuggestion> searchResults;
  LocationException? searchError;

  int getCurrentPositionCalls = 0;
  int searchPlacesCalls = 0;
  String? lastQuery;

  @override
  Future<LatLng> getCurrentPosition() async {
    getCurrentPositionCalls++;
    if (positionError != null) throw positionError!;
    final p = position;
    if (p == null) {
      throw const LocationException(LocationErrorKind.unavailable);
    }
    return p;
  }

  @override
  Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    searchPlacesCalls++;
    lastQuery = query;
    if (searchError != null) throw searchError!;
    return searchResults;
  }

  @override
  void dispose() {}
}

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  testWidgets('Confirm returns the initial / tapped pin location', (
    tester,
  ) async {
    LatLng? result;
    final initial = const LatLng(35.0, 139.0);

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<LatLng>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MapPickerScreen(
                        locationService: _FakeLocationService(),
                        initialLocation: initial,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Pick location'), findsOneWidget);
    expect(find.byKey(const Key('map_search_field')), findsOneWidget);
    expect(find.byKey(const Key('map_my_location')), findsOneWidget);

    await tester.tap(find.byKey(const Key('map_confirm')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.latitude, closeTo(initial.latitude, 0.0001));
    expect(result!.longitude, closeTo(initial.longitude, 0.0001));
  });

  testWidgets('Search lists results and selecting one moves the pin', (
    tester,
  ) async {
    LatLng? result;
    final place = PlaceSuggestion(
      displayName: 'Tokyo Station, Japan',
      location: const LatLng(35.6812, 139.7671),
    );
    final fake = _FakeLocationService(searchResults: [place]);

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<LatLng>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MapPickerScreen(
                        locationService: fake,
                        initialLocation: const LatLng(35.0, 139.0),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('map_search_field')),
      'Tokyo Station',
    );
    await tester.tap(find.byKey(const Key('map_search_submit')));
    await tester.pumpAndSettle();

    expect(fake.searchPlacesCalls, 1);
    expect(fake.lastQuery, 'Tokyo Station');
    expect(find.byKey(const Key('map_search_results')), findsOneWidget);
    expect(find.text('Tokyo Station, Japan'), findsOneWidget);

    await tester.tap(find.byKey(const Key('map_search_result_0')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('map_confirm')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.latitude, closeTo(place.location.latitude, 0.0001));
    expect(result!.longitude, closeTo(place.location.longitude, 0.0001));
  });

  testWidgets('Empty search shows no-results snackbar', (tester) async {
    final fake = _FakeLocationService(searchResults: const []);

    await tester.pumpWidget(_wrap(MapPickerScreen(locationService: fake)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('map_search_field')), 'zzz');
    await tester.tap(find.byKey(const Key('map_search_submit')));
    await tester.pumpAndSettle();

    expect(find.text('No places found for that search.'), findsOneWidget);
  });

  testWidgets('My location success updates pin and confirm returns it', (
    tester,
  ) async {
    LatLng? result;
    final gps = const LatLng(34.6937, 135.5023); // Osaka
    final fake = _FakeLocationService(position: gps);

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<LatLng>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MapPickerScreen(
                        locationService: fake,
                        initialLocation: const LatLng(35.0, 139.0),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('map_my_location')));
    await tester.pumpAndSettle();

    expect(fake.getCurrentPositionCalls, 1);

    await tester.tap(find.byKey(const Key('map_confirm')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.latitude, closeTo(gps.latitude, 0.0001));
    expect(result!.longitude, closeTo(gps.longitude, 0.0001));
  });

  testWidgets('My location permission denied shows snackbar', (tester) async {
    final fake = _FakeLocationService(
      positionError: const LocationException(
        LocationErrorKind.permissionDenied,
      ),
    );

    await tester.pumpWidget(_wrap(MapPickerScreen(locationService: fake)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('map_my_location')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Location permission denied'), findsOneWidget);
  });

  testWidgets('Search failure shows snackbar', (tester) async {
    final fake = _FakeLocationService(
      searchError: const LocationException(LocationErrorKind.searchFailed),
    );

    await tester.pumpWidget(_wrap(MapPickerScreen(locationService: fake)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('map_search_field')), 'x');
    await tester.tap(find.byKey(const Key('map_search_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Place search failed. Try again.'), findsOneWidget);
  });
}
