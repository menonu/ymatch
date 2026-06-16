// Part of #230: comprehensive E2E coverage for all user-facing
// features. This file covers the `System` area — a single endpoint
// (`GET /api/v1/system/status`) used to check the backend's liveness
// on app start.
//
// The test goes through `ApiClient.get()` directly (the only call
// site for this endpoint is `SystemController.refreshStatus()` in
// `home_screen.dart`, which uses the same method). This keeps the
// test minimal — there is no state to set up or verify beyond
// confirming the response shape.

@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';

ApiClient _api() {
  final config = ConfigService();
  config.setBaseUrlForTest(
    Platform.environment['E2E_API_URL'] ?? 'http://localhost:3000',
  );
  return ApiClient(config);
}

Future<bool> _waitForBackend(ApiClient api) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final r = await api.get('/api/v1/system/status');
      if (r is Map && r['backend_version'] != null) return true;
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

void main() {
  test('GET /api/v1/system/status returns backend_version + resources', () async {
    final api = _api();

    final ready = await _waitForBackend(api);
    expect(
      ready,
      isTrue,
      reason: 'Backend not reachable; start the e2e stack first',
    );

    final r = await api.get('/api/v1/system/status');
    expect(r, isA<Map>(), reason: 'status response should be a JSON object');

    final map = r as Map;
    expect(
      map['backend_version'],
      isA<String>(),
      reason: 'backend_version must be present and a string',
    );
    expect(
      map['backend_version']!.isNotEmpty,
      isTrue,
      reason: 'backend_version must not be empty',
    );
    // resources is optional; if present, must be a Map.
    if (map.containsKey('resources')) {
      expect(map['resources'], anyOf(isNull, isA<Map>()));
    }
  }, timeout: const Timeout(Duration(minutes: 1)));
}
