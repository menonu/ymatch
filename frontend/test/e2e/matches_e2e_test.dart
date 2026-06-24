// Part of #230: comprehensive E2E coverage for all user-facing
// features. This file covers the Matches area — the endpoints that
// list trades and drive the match state machine:
//   - GET  /api/v1/matches/user/{id}            (matchesProvider)
//   - GET  /api/v1/matches/user/{id}/counts     (notificationCountsProvider)
//   - POST /api/v1/matches/{id}/offer           (no provider; see trade_list_screen._submitOffer)
//   - POST /api/v1/matches/{id}/status          (no provider; see trade_list_screen._updateStatus)
//   - POST /api/v1/matches/{id}/apply-inventory (no provider; see trade_list_screen._applyInventory)
//
// The three POST endpoints are not wrapped in a Riverpod controller
// — they are called directly from `trade_list_screen.dart` with
// `client.post(...)`. To exercise the **same body shape** the screen
// sends (not a hand-built body in a test helper, which is exactly
// the gap #227 exploited), the lifecycle test below uses
// `OfferTradeRequest.toProto3Json()` for /offer and the same
// camelCase literal maps for /status and /apply-inventory.
//
// The match state machine is sequential: PENDING → OFFERED →
// ACCEPTED → COMPLETED → apply-inventory. The three POST endpoints
// cannot each be exercised in isolation without first driving the
// match into the right state, so the lifecycle is covered in a
// single test that walks the state machine. The two read-only
// endpoints (the providers) are covered by their own tests because
// they don't depend on match state.

@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/generated/models.pb.dart' as pb;
import 'package:frontend/providers/providers.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

String _uniqueName(String prefix) =>
    '${prefix}_${DateTime.now().microsecondsSinceEpoch}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues(<String, Object>{});

  late ApiClient api;
  late int user1Id;
  late int user2Id;
  late int eventId;
  late int cardA;
  late int cardB;
  late int matchId;

  setUpAll(() async {
    api = _api();
    final ready = await _waitForBackend(api);
    expect(
      ready,
      isTrue,
      reason: 'Backend not reachable; start the e2e stack first',
    );

    // Two users, one event, two merch items, and a cross-trade
    // inventory setup. The auto-matcher will create a PENDING match
    // between user1 and user2 because user1 TRADEs cardA + WANTs
    // cardB, and user2 TRADEs cardB + WANTs cardA.
    final u1 = await api.post('/api/v1/auth/guest', {
      'uuid': 'e2e_matches_u1_${DateTime.now().microsecondsSinceEpoch}',
      'deviceToken': 'e2e-matches',
    });
    user1Id = (u1 as Map)['id'] as int;

    final u2 = await api.post('/api/v1/auth/guest', {
      'uuid': 'e2e_matches_u2_${DateTime.now().microsecondsSinceEpoch}',
      'deviceToken': 'e2e-matches',
    });
    user2Id = (u2 as Map)['id'] as int;
    expect(user2Id, isNot(user1Id));

    final e = await api.post('/api/v1/events', {
      'name': 'E2E matches event',
      'creatorId': user1Id,
    });
    eventId = (e as Map)['id'] as int;

    Future<int> createMerch(String tag) async {
      final r = await api.post('/api/v1/events/$eventId/merch', {
        'name': _uniqueName('e2e_matches_$tag'),
        'creatorId': user1Id,
        'groupName': 'e2e-matches',
      });
      return (r as Map)['id'] as int;
    }

    cardA = await createMerch('cardA');
    cardB = await createMerch('cardB');

    Future<void> setInventory(int userId, int merchId, String status) async {
      await api.post('/api/v1/user/inventory', {
        'userId': userId,
        'merchId': merchId,
        'status': status,
        'quantity': 1,
      });
    }

    await setInventory(user1Id, cardA, 'TRADE');
    await setInventory(user1Id, cardB, 'WANT');
    await setInventory(user2Id, cardB, 'TRADE');
    await setInventory(user2Id, cardA, 'WANT');

    // Wait for the auto-matcher to create a PENDING match. The
    // matcher is a background job; 90s is a generous upper bound
    // (in practice it fires within a few seconds).
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      final r = await api.get('/api/v1/matches/user/$user1Id');
      final matches = (r as List).cast<Map<String, dynamic>>();
      final pending = matches.where((m) => m['status'] == 'PENDING').toList();
      if (pending.isNotEmpty) {
        matchId = pending.first['id'] as int;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(matchId, isPositive,
        reason: 'No PENDING match appeared within 90s — matcher did not run');
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [apiClientProvider.overrideWith((ref) => api)],
    );
  }

  Future<String> getMatchStatus(int matchId) async {
    final r = await api.get('/api/v1/matches/user/$user1Id');
    final matches = (r as List).cast<Map<String, dynamic>>();
    final m = matches.firstWhere(
      (m) => m['id'] == matchId,
      orElse: () => throw StateError('match $matchId not found'),
    );
    return m['status'] as String;
  }

  Future<bool> getInventoryApplied(int matchId) async {
    final r = await api.get('/api/v1/matches/user/$user1Id');
    final matches = (r as List).cast<Map<String, dynamic>>();
    final m = matches.firstWhere(
      (m) => m['id'] == matchId,
      orElse: () => throw StateError('match $matchId not found'),
    );
    return (m['inventoryApplied'] ?? false) as bool;
  }

  test('matchesProvider GETs /matches/user/{id} and returns the PENDING match',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final matches =
        await container.read(matchesProvider(user1Id).future);
    expect(matches, isA<List>());
    final pending = matches
        .where((m) => m.id == matchId && m.status == 'PENDING')
        .toList();
    expect(pending, hasLength(1),
        reason: 'setUpAll should have produced a PENDING match visible to '
            'matchesProvider for user1');
  });

  test(
      'notificationCountsProvider GETs /matches/user/{id}/counts and returns counts',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final counts =
        await container.read(notificationCountsProvider(user1Id).future);
    // NotificationCounts is a proto message; a non-null value with
    // pendingMatches >= 1 proves the wire contract is right (the
    // setUpAll match contributes to the pending count for user1).
    expect(counts.pendingMatches, greaterThanOrEqualTo(1));
  });

  test(
      'full match lifecycle: /offer, /status, /status, /apply-inventory '
      'drive the state machine end-to-end', () async {
    // Each step uses the **same body shape** the screen sends
    // (trade_list_screen.dart), not a hand-built body.
    //
    // 1. PENDING → OFFERED  via POST /matches/{id}/offer
    final offer = pb.OfferTradeRequest()
      ..userId = user1Id
      ..items.addAll([
        pb.OfferItem()
          ..merchId = cardA
          ..giverUserId = user1Id
          ..quantity = 1,
        pb.OfferItem()
          ..merchId = cardB
          ..giverUserId = user2Id
          ..quantity = 1,
      ]);
    await api.post(
      '/api/v1/matches/$matchId/offer',
      offer.toProto3Json() as Map<String, dynamic>,
    );
    expect(await getMatchStatus(matchId), 'OFFERED');

    // 2. OFFERED → ACCEPTED  via POST /matches/{id}/status
    //    The non-proposer (user2) accepts the balanced proposal.
    await api.post('/api/v1/matches/$matchId/status', {
      'status': 'ACCEPTED',
      'userId': user2Id,
    });
    expect(await getMatchStatus(matchId), 'ACCEPTED');

    // 3. ACCEPTED → COMPLETED  via POST /matches/{id}/status
    await api.post('/api/v1/matches/$matchId/status', {
      'status': 'COMPLETED',
      'userId': user1Id,
    });
    expect(await getMatchStatus(matchId), 'COMPLETED');

    // 4. Apply inventory  via POST /matches/{id}/apply-inventory
    await api.post('/api/v1/matches/$matchId/apply-inventory', {
      'userId': user1Id,
    });
    expect(await getInventoryApplied(matchId), isTrue);
  });
}
