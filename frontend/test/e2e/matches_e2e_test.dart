// Part of #230: comprehensive E2E coverage for all user-facing
// features. This file covers the Matches area — the endpoints that
// list trades and drive the match state machine:
//   - GET  /api/v1/matches/user/{id}            (matchesProvider)
//   - GET  /api/v1/matches/user/{id}/counts     (notificationCountsProvider)
//   - POST /api/v1/matches/{id}/offer           (MatchController.submitOffer)
//   - POST /api/v1/matches/{id}/status          (MatchController.updateStatus)
//   - POST /api/v1/matches/{id}/apply-inventory (MatchController.applyInventory)
//
// #241: the three lifecycle mutations go through MatchController so
// the test exercises the same proto body shapes and invalidation
// path the trades UI uses (not hand-built raw maps).
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
import 'helpers/e2e_users.dart';

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

    // One event + two merch items (created by the seeded moderator, the
    // only actor that can pass the `event.create` / `merch.create` gates),
    // then two FRESH guests cross-trade them. The match forms between the
    // two fresh guests (distinct uuids per file), not the moderator, so
    // the "first PENDING match for user1" probe below is race-free even
    // though `flutter test` runs e2e files concurrently against this one
    // shared backend.
    final modId = await loginE2EModerator(api);
    final e = await api.post('/api/v1/events', {
      'name': 'E2E matches event',
      'creatorId': modId,
    });
    eventId = (e as Map)['id'] as int;

    Future<int> createMerch(String tag) async {
      final r = await api.post('/api/v1/events/$eventId/merch', {
        'name': _uniqueName('e2e_matches_$tag'),
        'creatorId': modId,
        'groupName': 'e2e-matches',
      });
      return (r as Map)['id'] as int;
    }

    cardA = await createMerch('cardA');
    cardB = await createMerch('cardB');

    user1Id = await createE2EGuest(
      api,
      'e2e_matches_u1_${DateTime.now().microsecondsSinceEpoch}',
    );
    user2Id = await createE2EGuest(
      api,
      'e2e_matches_u2_${DateTime.now().microsecondsSinceEpoch}',
    );
    expect(user2Id, isNot(user1Id));

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
    expect(
      matchId,
      isPositive,
      reason: 'No PENDING match appeared within 90s — matcher did not run',
    );
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

  test(
    'matchesProvider GETs /matches/user/{id} and returns the PENDING match',
    () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final matches = await container.read(matchesProvider(user1Id).future);
      expect(matches, isA<List>());
      final pending = matches
          .where((m) => m.id == matchId && m.status == 'PENDING')
          .toList();
      expect(
        pending,
        hasLength(1),
        reason:
            'setUpAll should have produced a PENDING match visible to '
            'matchesProvider for user1',
      );
    },
  );

  test(
    'notificationCountsProvider GETs /matches/user/{id}/counts and returns counts',
    () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final counts = await container.read(
        notificationCountsProvider(user1Id).future,
      );
      // NotificationCounts is a proto message; a non-null value with
      // pendingMatches >= 1 proves the wire contract is right (the
      // setUpAll match contributes to the pending count for user1).
      expect(counts.pendingMatches, greaterThanOrEqualTo(1));
    },
  );

  test(
    'full match lifecycle via MatchController: offer → accept → complete → apply-inventory',
    () async {
      // Drive mutations through MatchController so the test locks the
      // same proto body shapes and invalidation path as trade_list_screen.
      final container = makeContainer();
      addTearDown(container.dispose);
      final controller = container.read(matchControllerProvider.notifier);

      // 1. PENDING → OFFERED
      await controller.submitOffer(user1Id, matchId, [
        pb.OfferItem()
          ..merchId = cardA
          ..giverUserId = user1Id
          ..quantity = 1,
        pb.OfferItem()
          ..merchId = cardB
          ..giverUserId = user2Id
          ..quantity = 1,
      ]);
      expect(container.read(matchControllerProvider).hasError, isFalse);
      expect(await getMatchStatus(matchId), 'OFFERED');

      // 2. OFFERED → ACCEPTED  (non-proposer accepts)
      await controller.updateStatus(user2Id, matchId, 'ACCEPTED');
      expect(container.read(matchControllerProvider).hasError, isFalse);
      expect(await getMatchStatus(matchId), 'ACCEPTED');

      // 3. ACCEPTED → COMPLETED
      await controller.updateStatus(user1Id, matchId, 'COMPLETED');
      expect(container.read(matchControllerProvider).hasError, isFalse);
      expect(await getMatchStatus(matchId), 'COMPLETED');

      // 4. Apply inventory
      await controller.applyInventory(user1Id, matchId);
      expect(container.read(matchControllerProvider).hasError, isFalse);
      expect(await getInventoryApplied(matchId), isTrue);
    },
  );
}
