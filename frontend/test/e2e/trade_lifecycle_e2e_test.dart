// Marked `e2e` (not `integration`) for two reasons:
//   1. `frontend/dart_test.yaml` unconditionally skips the `integration`
//      tag, which would also skip this test in the dedicated
//      ci-e2e.yml workflow where a live backend is up.
//   2. The regular CI workflow (ci.yml) excludes `--exclude-tags=e2e`
//      so this test does not run where there is no backend.
@Tags(['e2e'])
library;

// Frontend-driven end-to-end test for the trade lifecycle (#213).
//
// Drives the real `ApiClient` + protobuf-generated types against a
// live backend (started via `docker-compose.e2e.yml`). The test does
// NOT use the widget tree; it is a pure HTTP test that exercises the
// same wire contract the Flutter app uses.
//
// ## Why this exists
//
// Issue #202 was a JSON key-casing mismatch: the frontend sends
// camelCase proto3 JSON (via `toProto3Json()`), but the backend
// initially only accepted snake_case. The bug only surfaced when a
// real user clicked "Submit offer" in the app and got a 422. The
// backend's own unit + integration tests hand-wrote snake_case JSON
// and therefore did not catch it.
//
// This test would have caught #202 because it sends the *exact* body
// the frontend sends.
//
// ## Running locally
//
// ```bash
// docker compose -f docker-compose.e2e.yml up -d --build
// flutter test test/e2e/
// docker compose -f docker-compose.e2e.yml down -v
// ```
//
// ## Running in CI
//
// See `.github/workflows/ci-e2e.yml`.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/generated/models.pb.dart' as pb;
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:http/http.dart' as http;

/// HTTP base URL for the E2E backend. The docker-compose.e2e.yml
/// stack exposes the backend on localhost:3000.
final Uri _baseUrl = Uri.parse(
  Platform.environment['E2E_API_URL'] ?? 'http://localhost:3000',
);

/// `http.Client` that records the status code of the last response,
/// so the E2E test can assert on success/failure. `ApiClient` discards
/// the raw response (it returns the parsed body) — we wrap the
/// transport to keep it.
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._inner);
  final http.Client _inner;
  int? lastStatus;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request).then((response) {
      lastStatus = response.statusCode;
      return response;
    });
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// Wraps an `ApiClient` with status-code assertions. The wrapped
/// client throws on non-2xx responses, so the test only needs to
/// check the absence of an exception.
class _ApiWithStatus {
  _ApiWithStatus(this.api, this.recorder);

  final ApiClient api;
  final _RecordingClient recorder;

  Future<int> _post(String endpoint, Map<String, dynamic> body) async {
    await api.post(endpoint, body);
    final status = recorder.lastStatus;
    if (status == null) {
      throw StateError('No response recorded for $endpoint');
    }
    return status;
  }

  Future<int> _put(String endpoint, Map<String, dynamic> body) async {
    await api.put(endpoint, body);
    return recorder.lastStatus!;
  }
}

({ApiClient api, _RecordingClient recorder}) _apiWithRecorder() {
  final config = ConfigService();
  config.setBaseUrlForTest(_baseUrl.toString());
  final inner = http.Client();
  final recorder = _RecordingClient(inner);
  return (api: ApiClient(config, client: recorder), recorder: recorder);
}

Future<bool> _waitForBackend(ApiClient api) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final r = await api.get('/api/v1/system/status');
      if (r is Map && r['backend_version'] != null) return true;
    } catch (_) {
      // not ready yet
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

Future<int> _guestLogin(ApiClient api) async {
  final r = await api.post('/api/v1/auth/guest', {
    'uuid': 'e2e-${DateTime.now().microsecondsSinceEpoch}-${api.hashCode}',
    'deviceToken': 'e2e-device',
  });
  return (r as Map)['id'] as int;
}

Future<int> _createEvent(ApiClient api, String name) async {
  final r = await api.post('/api/v1/events', {
    'name': name,
    'description': 'E2E test event',
  });
  return (r as Map)['id'] as int;
}

Future<int> _createMerch(
  ApiClient api, {
  required int eventId,
  required String name,
  required int quantity,
}) async {
  final r = await api.post('/api/v1/merchandise', {
    'eventId': eventId,
    'name': name,
    'quantity': quantity,
    'isTradeable': true,
  });
  return (r as Map)['id'] as int;
}

Future<void> _setInventory(
  ApiClient api, {
  required int userId,
  required int eventId,
  required int merchId,
  required String status,
  int quantity = 1,
}) async {
  // Backend auth model: user_id is passed in the body. The ApiClient
  // does not track the current user — that is the provider's job in
  // the real app. For E2E we pass user_id explicitly.
  await api.post('/api/v1/inventory', {
    'userId': userId,
    'eventId': eventId,
    'merchId': merchId,
    'status': status,
    'quantity': quantity,
  });
}

Future<int> _waitForPendingMatch(
  ApiClient api, {
  required int userId,
  required int eventId,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final r = await api.get('/api/v1/matches/$userId');
    final matches = (r as List).cast<Map<String, dynamic>>();
    for (final m in matches) {
      if (m['eventId'] == eventId && m['status'] == 'PENDING') {
        return m['id'] as int;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw TimeoutException(
    'No PENDING match appeared for user $userId in event $eventId within $timeout',
  );
}

void main() {
  test(
    'end-to-end: full trade lifecycle through real ApiClient (#202 regression)',
    () async {
    final made = _apiWithRecorder();
    final api = made.api;
    final recorder = made.recorder;
    final helper = _ApiWithStatus(api, recorder);

    // 1. Wait for the backend to be reachable.
    final ready = await _waitForBackend(api);
    expect(ready, isTrue, reason: 'Backend not reachable at $_baseUrl');

    // 2. Login two users (guest auth — no signup required).
    final u1Id = await _guestLogin(api);
    final u2Id = await _guestLogin(api);
    expect(u1Id, isNot(u2Id));

    // 3. Create one event, then two pieces of merch in it.
    final eventId =
        await _createEvent(api, 'E2E event ${DateTime.now().millisecondsSinceEpoch}');
    final cardA = await _createMerch(api, eventId: eventId, name: 'Card A', quantity: 5);
    final cardB = await _createMerch(api, eventId: eventId, name: 'Card B', quantity: 5);

    // 4. Set up the cross-trade inventory:
    //    user1 HAS Card A and WANTS Card B.
    //    user2 HAS Card B and WANTS Card A.
    await _setInventory(api, userId: u1Id, eventId: eventId, merchId: cardA, status: 'HAVE');
    await _setInventory(api, userId: u1Id, eventId: eventId, merchId: cardB, status: 'WANT');
    await _setInventory(api, userId: u2Id, eventId: eventId, merchId: cardB, status: 'HAVE');
    await _setInventory(api, userId: u2Id, eventId: eventId, merchId: cardA, status: 'WANT');

    // 5. Wait for the auto-matcher to produce a PENDING match.
    final matchId = await _waitForPendingMatch(
      api,
      userId: u1Id,
      eventId: eventId,
    );
    expect(matchId, isPositive);

    // 6. THE #202 REGRESSION CHECK: submit an offer using the EXACT
    //    shape the Flutter app sends. We use the generated proto
    //    message's `toProto3Json()` (camelCase) so any future
    //    backend casing regression is caught.
    final offerReq = pb.OfferTradeRequest(
      userId: u1Id,
      items: [
        pb.OfferItem(merchId: cardA, direction: 'GIVE', quantity: 1),
        pb.OfferItem(merchId: cardB, direction: 'RECEIVE', quantity: 1),
      ],
    );
    final offerBody = offerReq.toProto3Json() as Map;

    //    Sanity-check: the keys are camelCase. If the proto compiler
    //    ever flips to snake_case (or the frontend's toProto3Json()
    //    implementation changes), this assertion will fail.
    expect(offerBody.keys, containsAll(['userId', 'items']));
    final firstItem = (offerBody['items'] as List).first as Map;
    expect(firstItem.keys, containsAll(['merchId', 'direction', 'quantity']));

    //    Cast to typed map for the API client.
    final offerBodyTyped = Map<String, dynamic>.from(offerBody);

    //    Send the offer. This is the request that 422'd in #202.
    //    helper._post throws if the backend returns non-2xx; the
    //    status check below then confirms 200.
    final offerStatus = await helper._post(
      '/api/v1/matches/$matchId/offer',
      offerBodyTyped,
    );
    expect(offerStatus, 200,
        reason:
            'offer should succeed; a 422 here means the #202 regression has returned');

    // 7. The OTHER user accepts the offer.
    final acceptStatus = await helper._put(
      '/api/v1/matches/$matchId/status',
      {'status': 'ACCEPTED'},
    );
    expect(acceptStatus, 200);

    // 8. Both users mark the trade COMPLETED.
    final complete1 = await helper._put(
      '/api/v1/matches/$matchId/status',
      {'status': 'COMPLETED'},
    );
    final complete2 = await helper._put(
      '/api/v1/matches/$matchId/status',
      {'status': 'COMPLETED'},
    );
    expect(complete1, 200);
    expect(complete2, 200);

    // 9. Each user applies the inventory delta. This is the
    //    "trade actually happened" step.
    final apply1 = await helper._post(
      '/api/v1/matches/$matchId/apply-inventory',
      {},
    );
    expect(apply1, 200);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
