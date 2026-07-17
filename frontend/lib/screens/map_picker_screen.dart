import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/app_localizations.dart';
import '../services/location_service.dart';

/// Full-screen map for picking a meetup point to share in chat.
///
/// Supports tap-to-pin, GPS "my location", and place/address search.
/// [locationService] is injectable for widget tests (no real GPS/network).
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({
    super.key,
    this.locationService,
    this.initialLocation = DefaultLocationService.defaultCenter,
  });

  /// When null, a [DefaultLocationService] is created.
  final LocationService? locationService;

  /// Initial map center and pin (defaults to Tokyo).
  final LatLng initialLocation;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  late final LocationService _locationService;
  late final MapController _mapController;
  late final TextEditingController _searchController;

  late LatLng _selectedLocation;
  List<PlaceSuggestion> _searchResults = const [];
  bool _searching = false;
  bool _locating = false;
  bool _mapReady = false;

  static const double _pickZoom = 15.0;

  @override
  void initState() {
    super.initState();
    _locationService = widget.locationService ?? DefaultLocationService();
    _mapController = MapController();
    _searchController = TextEditingController();
    _selectedLocation = widget.initialLocation;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _setPin(LatLng point, {bool moveCamera = true}) {
    setState(() {
      _selectedLocation = point;
    });
    if (moveCamera && _mapReady) {
      _mapController.move(point, _pickZoom);
    }
  }

  Future<void> _onMyLocation() async {
    if (_locating) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _locating = true);
    try {
      final pos = await _locationService.getCurrentPosition();
      if (!mounted) return;
      _setPin(pos);
      setState(() {
        _searchResults = const [];
      });
    } on LocationException catch (e) {
      if (!mounted) return;
      final message = switch (e.kind) {
        LocationErrorKind.permissionDenied => l10n.mapLocationPermissionDenied,
        LocationErrorKind.serviceDisabled => l10n.mapLocationServiceDisabled,
        LocationErrorKind.unavailable => l10n.mapLocationUnavailable,
        LocationErrorKind.searchFailed => l10n.mapLocationUnavailable,
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.mapLocationUnavailable)));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _onSearch([String? raw]) async {
    final query = (raw ?? _searchController.text).trim();
    if (query.isEmpty || _searching) return;

    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _searching = true;
      _searchResults = const [];
    });
    // Dismiss keyboard so results stay visible on small screens.
    FocusScope.of(context).unfocus();

    try {
      final results = await _locationService.searchPlaces(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
      if (results.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.mapSearchNoResults)));
      }
    } on LocationException {
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.mapSearchFailed)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.mapSearchFailed)));
    }
  }

  void _selectSearchResult(PlaceSuggestion place) {
    _searchController.text = place.displayName;
    setState(() => _searchResults = const []);
    _setPin(place.location);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mapPickerTitle),
        actions: [
          TextButton(
            key: const Key('map_confirm'),
            onPressed: () {
              Navigator.pop(context, _selectedLocation);
            },
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
            ),
            child: Text(
              l10n.confirm,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedLocation,
              initialZoom: 13.0,
              onMapReady: () {
                _mapReady = true;
              },
              onTap: (tapPosition, point) {
                setState(() {
                  _selectedLocation = point;
                  _searchResults = const [];
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.ymatch.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _selectedLocation,
                    width: 80,
                    height: 80,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.red,
                      size: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const Key('map_search_field'),
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _onSearch,
                    decoration: InputDecoration(
                      hintText: l10n.mapSearchHint,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              key: const Key('map_search_submit'),
                              tooltip: l10n.mapSearchHint,
                              icon: const Icon(Icons.arrow_forward),
                              onPressed: () => _onSearch(),
                            ),
                    ),
                  ),
                  if (_searchResults.isNotEmpty) ...[
                    const Divider(height: 1),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.builder(
                        key: const Key('map_search_results'),
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final place = _searchResults[index];
                          return ListTile(
                            key: Key('map_search_result_$index'),
                            leading: const Icon(Icons.place_outlined),
                            title: Text(
                              place.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectSearchResult(place),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton(
              key: const Key('map_my_location'),
              heroTag: 'map_my_location',
              tooltip: l10n.mapMyLocationTooltip,
              onPressed: _locating ? null : _onMyLocation,
              child: _locating
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}
