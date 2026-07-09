// Frontend-driven end-to-end test for the #297 trade negotiation state
// machine. Tagged `e2e` (not `integration`) for the same two reasons as
// `trade_lifecycle_e2e_test.dart` (see its header): `dart_test.yaml`
// unconditionally skips `integration`, and `ci.yml` excludes `e2e`; the
// dedicated `ci-e2e.yml` workflow opts back in with `--run-skipped`
// against a live backend.
//
// ## Why this exists alongside the backend integration test
//
// `test_trade_negotiation_counter_offer_and_balance` in
// `backend/tests/api_tests.rs` walks the negotiation state machine, but
// it hand-writes the JSON bodies. Issue #202 was a wire-contract bug
// (snake_case vs camelCase) that the backend tests could not catch
// precisely because they hand-wrote the body. This file drives the
// **exact** wire shape the Flutter app sends — `OfferTradeRequest
// .toProto3Json()` for `/offer` and the same camelCase literal maps the
// screen sends for `/status` and `/apply-inventory` — so a future
// frontend serialization regression in the new partial-upsert / balance
// contract is caught here.
//
// ## What it covers
//
// Every #297 behavior through the real `ApiClient` + protobuf wire path:
//   - opening proposal (OFFERED, offeredBy = proposer)
//   - counter-offer accumulates legs (unspecified legs persist)
//   - accept gated on non-proposer AND balanced (both 400 paths)
//   - proposer cannot counter their own open proposal (400)
//   - partial update: quantity 0 removes a leg
//   - the three offer modes (give-only / receive-only / both)
//   - reject from PENDING and from OFFERED (legs cleared)
//   - per-leg want-quantity cap (#294) enforced on propose (400)
//   - non-participant authz: outsider cannot propose/accept (403)
//   - full happy path: open → accept → complete → apply both sides
//
// ## Running locally
//
// ```bash
// docker compose -f docker-compose.e2e.yml up -d --build
// flutter test --run-skipped test/e2e/trade_negotiation_e2e_test.dart
// docker compose -f docker-compose.e2e.yml down -v
// ```
//
// Each scenario provisions its own isolated match (unique event + merch
// per scenario, so the auto-matcher only pairs within a scenario). The
// e2e stack runs the matcher every 5s (MATCHING_INTERVAL_SECONDS), so a
// PENDING match appears within a few seconds.

@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/generated/models.pb.dart' as pb;
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:http/http.dart' as http;
import 'helpers/e2e_users.dart';

/// HTTP base URL for the E2E backend (`docker-compose.e2e.yml` exposes
/// the backend on localhost:3000).
final Uri _baseUrl = Uri.parse(
  Platform.environment['E2E_API_URL'] ?? 'http://localhost:3000',
);

/// Monotonic nonce so two guest logins in the same microsecond never
/// collide on the `uuid` (which would silently return the same user).
int _nonce = 0;
String _uniqueUuid(String tag) =>
    'e2e-neg-${DateTime.now().microsecondsSinceEpoch}-${_nonce++}-$tag';

/// `http.Client` that records the status code of the last response. The
/// `ApiClient` discards the raw response (it returns the parsed body or
/// throws on non-2xx), so we wrap the transport to keep the status code
/// — the rejection scenarios below assert on 400/403, which `ApiClient
/// .post` turns into a thrown exception before returning.
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

/// Wraps an `ApiClient` with access to the recorded status code. The
/// `_postStatus` helper below reads `recorder.lastStatus` after each
/// call, catching the exception `ApiClient.post` raises on non-2xx —
/// the recorder captured the real HTTP status in `send()` before that
/// throw, so 400/403 are observable.
class _Api {
  _Api(this.api, this.recorder);
  final ApiClient api;
  final _RecordingClient recorder;
}

_Api _newApi() {
  final config = ConfigService();
  config.setBaseUrlForTest(_baseUrl.toString());
  final inner = http.Client();
  final recorder = _RecordingClient(inner);
  return _Api(ApiClient(config, client: recorder), recorder);
}

/// POST and return the recorded HTTP status code, whether or not the
/// request succeeded. `ApiClient.post` throws on non-2xx; the recorder
/// has already captured the status by then, so we swallow the throw and
/// read it.
Future<int> _postStatus(_Api a, String endpoint, Map<String, dynamic> body) async {
  try {
    await a.api.post(endpoint, body);
  } catch (_) {
    // Expected for non-2xx; the recorder captured the status in send().
  }
  final status = a.recorder.lastStatus;
  if (status == null) {
    throw StateError('No response recorded for $endpoint');
  }
  return status;
}

/// Submit a proposal through the **same wire shape** the Flutter app
/// sends (`OfferTradeRequest.toProto3Json()`), returning the HTTP status.
Future<int> _offer(
  _Api a,
  int matchId,
  int proposerId,
  List<pb.OfferItem> items,
) async {
  final req = pb.OfferTradeRequest(userId: proposerId, items: items);
  return _postStatus(
    a,
    '/api/v1/matches/$matchId/offer',
    req.toProto3Json() as Map<String, dynamic>,
  );
}

/// Drive a state transition through the same body shape the screen sends
/// (`trade_list_screen._updateStatus` builds `{'status': ..., 'userId': ...}`).
Future<int> _setStatus(_Api a, int matchId, int userId, String status) =>
    _postStatus(a, '/api/v1/matches/$matchId/status', {
      'status': status,
      'userId': userId,
    });

Future<int> _applyInventory(_Api a, int matchId, int userId) =>
    _postStatus(a, '/api/v1/matches/$matchId/apply-inventory', {
      'userId': userId,
    });

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

Future<int> _guestLogin(ApiClient api, {required String tag}) async {
  final r = await api.post('/api/v1/auth/guest', {
    'uuid': _uniqueUuid(tag),
    'deviceToken': 'e2e-neg-device',
  });
  return (r as Map)['id'] as int;
}

Future<int> _createEvent(ApiClient api, {required String name, required int creatorId}) async {
  final r = await api.post('/api/v1/events', {'name': name, 'creatorId': creatorId});
  return (r as Map)['id'] as int;
}

Future<int> _createMerch(
  ApiClient api, {
  required int eventId,
  required String name,
  required int creatorId,
  required String groupName,
}) async {
  // ADR 0005: `creatorId` is the caller identity the `merch.create` gate
  // authorizes against (the moderator / event creator).
  final r = await api.post('/api/v1/events/$eventId/merch', {
    'name': name,
    'creatorId': creatorId,
    'groupName': groupName,
  });
  return (r as Map)['id'] as int;
}

Future<void> _setInventory(
  ApiClient api, {
  required int userId,
  required int merchId,
  required String status,
  int quantity = 1,
}) async {
  await api.post('/api/v1/user/inventory', {
    'userId': userId,
    'merchId': merchId,
    'status': status,
    'quantity': quantity,
  });
}

/// A freshly provisioned PENDING match between two users, with the two
/// merch ids they cross-trade. Each field is captured so a scenario can
/// drive the state machine without re-querying for the ids.
class _Match {
  final int id;
  final int u1;
  final int u2;
  final int cardA; // u1 TRADEs, u2 WANTs
  final int cardB; // u2 TRADEs, u1 WANTs
  _Match(this.id, this.u1, this.u2, this.cardA, this.cardB);
}

/// Provision one isolated PENDING match: two fresh users, a fresh event
/// with two fresh merch items, and a cross-trade inventory (u1 TRADE A /
/// WANT B; u2 TRADE B / WANT A). The unique event + merch per call means
/// the auto-matcher can only pair within this provision — scenarios
/// never collide with each other. The four quantity params let the
/// want-qty-cap scenarios start with more units than the other side wants
/// (the precondition for over-cap legs).
Future<_Match> _provisionPendingMatch(
  ApiClient api, {
  required String tag,
  int u1TradeAQty = 1,
  int u1WantBQty = 1,
  int u2TradeBQty = 1,
  int u2WantAQty = 1,
}) async {
  // The event + merch are created by the seeded moderator (the only
  // actor that passes the `event.create` / `merch.create` gates); the two
  // FRESH guests (distinct uuids per scenario) cross-trade them, so the
  // match forms between u1 and u2 — race-free under concurrent e2e files
  // even though the moderator is shared.
  final modId = await loginE2EModerator(api);
  final eventId = await _createEvent(
    api,
    name: 'neg-event-$tag-$_nonce',
    creatorId: modId,
  );
  final cardA = await _createMerch(
    api,
    eventId: eventId,
    name: 'A-$tag',
    creatorId: modId,
    groupName: 'neg-$tag',
  );
  final cardB = await _createMerch(
    api,
    eventId: eventId,
    name: 'B-$tag',
    creatorId: modId,
    groupName: 'neg-$tag',
  );

  final u1 = await _guestLogin(api, tag: '${tag}_u1');
  final u2 = await _guestLogin(api, tag: '${tag}_u2');
  expect(u2, isNot(u1));

  await _setInventory(api, userId: u1, merchId: cardA, status: 'TRADE', quantity: u1TradeAQty);
  await _setInventory(api, userId: u1, merchId: cardB, status: 'WANT', quantity: u1WantBQty);
  await _setInventory(api, userId: u2, merchId: cardB, status: 'TRADE', quantity: u2TradeBQty);
  await _setInventory(api, userId: u2, merchId: cardA, status: 'WANT', quantity: u2WantAQty);

  // Wait for the auto-matcher (every 5s in the e2e stack) to produce the
  // PENDING match for u1. 30s is a generous upper bound.
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  int? matchId;
  while (DateTime.now().isBefore(deadline)) {
    final r = await api.get('/api/v1/matches/user/$u1');
    final matches = (r as List).cast<Map<String, dynamic>>();
    final pending = matches.where((m) => m['status'] == 'PENDING');
    if (pending.isNotEmpty) {
      matchId = pending.first['id'] as int;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  if (matchId == null) {
    fail('No PENDING match appeared for $tag within 30s — matcher did not run');
  }
  return _Match(matchId, u1, u2, cardA, cardB);
}

/// Read the live match as seen by `userId` (the listing is scoped to the
/// requesting user — `offeredBy` and `inventoryApplied` are present, and
/// `selectedItems` holds the current absolute legs).
Future<Map<String, dynamic>> _getMatch(ApiClient api, int userId, int matchId) async {
  final r = await api.get('/api/v1/matches/user/$userId');
  final matches = (r as List).cast<Map<String, dynamic>>();
  return matches.firstWhere(
    (m) => m['id'] == matchId,
    orElse: () => throw StateError('match $matchId not found for user $userId'),
  );
}

/// Σ quantity of legs where `giverUserId == giver` — the total that
/// `giver` gives in the current proposal.
int _giveTotal(Map<String, dynamic> match, int giver) {
  final items = (match['selectedItems'] as List?) ?? const [];
  return items
      .whereType<Map>()
      .where((i) => i['giverUserId'] == giver)
      .fold(0, (a, i) => a + ((i['quantity'] as num?) ?? 0).toInt());
}

bool _isBalanced(Map<String, dynamic> match, int u1, int u2) {
  final a = _giveTotal(match, u1);
  final b = _giveTotal(match, u2);
  return a == b && a > 0;
}

void main() {
  test('end-to-end negotiation: open → rejections → counter to balance → accept (#297)', () async {
    final a = _newApi();
    expect(await _waitForBackend(a.api), isTrue, reason: 'Backend not reachable at $_baseUrl');
    final m = await _provisionPendingMatch(a.api, tag: 'loop');

    // 1. u1 opens give-only (unbalanced: u1 gives 1, u2 gives 0).
    expect(
      await _offer(a, m.id, m.u1, [
        pb.OfferItem(merchId: m.cardA, giverUserId: m.u1, quantity: 1),
      ]),
      200,
    );
    var match = await _getMatch(a.api, m.u1, m.id);
    expect(match['status'], 'OFFERED');
    expect(match['offeredBy'], m.u1);
    expect(_giveTotal(match, m.u1), 1);
    expect(_giveTotal(match, m.u2), 0);
    expect(_isBalanced(match, m.u1, m.u2), isFalse);

    // 2. u2 (non-proposer) cannot accept an unbalanced proposal → 400.
    expect(await _setStatus(a, m.id, m.u2, 'ACCEPTED'), 400);
    // 3. u1 (the proposer) cannot accept their own proposal → 400.
    expect(await _setStatus(a, m.id, m.u1, 'ACCEPTED'), 400);
    // 4. u1 cannot counter their own open proposal → 400 (must wait).
    expect(
      await _offer(a, m.id, m.u1, [
        pb.OfferItem(merchId: m.cardA, giverUserId: m.u1, quantity: 1),
      ]),
      400,
    );

    // 5. u2 counter-offers: add their own give of cardB. Legs ACCUMULATE
    //    (u1's give of cardA persists), so the proposal is now balanced
    //    1:1, and offeredBy flips to u2.
    expect(
      await _offer(a, m.id, m.u2, [
        pb.OfferItem(merchId: m.cardB, giverUserId: m.u2, quantity: 1),
      ]),
      200,
    );
    match = await _getMatch(a.api, m.u1, m.id);
    expect(match['status'], 'OFFERED');
    expect(match['offeredBy'], m.u2);
    expect(_giveTotal(match, m.u1), 1);
    expect(_giveTotal(match, m.u2), 1);
    expect(_isBalanced(match, m.u1, m.u2), isTrue);

    // 6. u1 is now the non-proposer and accepts the balanced proposal.
    expect(await _setStatus(a, m.id, m.u1, 'ACCEPTED'), 200);
    match = await _getMatch(a.api, m.u1, m.id);
    expect(match['status'], 'ACCEPTED');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('counter-offer partial update: qty 0 removes a leg, unspecified legs persist (#297)', () async {
    final a = _newApi();
    final m = await _provisionPendingMatch(a.api, tag: 'partial');

    // 1. u1 opens "both": give cardA + receive cardB (giver=u2). 1:1.
    expect(
      await _offer(a, m.id, m.u1, [
        pb.OfferItem(merchId: m.cardA, giverUserId: m.u1, quantity: 1),
        pb.OfferItem(merchId: m.cardB, giverUserId: m.u2, quantity: 1),
      ]),
      200,
    );
    var match = await _getMatch(a.api, m.u1, m.id);
    expect(_giveTotal(match, m.u1), 1);
    expect(_giveTotal(match, m.u2), 1);
    expect(_isBalanced(match, m.u1, m.u2), isTrue);

    // 2. u2 (non-proposer) counters with ONLY the cardB leg at qty 0 →
    //    that leg is removed; u1's give of cardA (unspecified) persists.
    //    The proposal is now unbalanced 1:0.
    expect(
      await _offer(a, m.id, m.u2, [
        pb.OfferItem(merchId: m.cardB, giverUserId: m.u2, quantity: 0),
      ]),
      200,
    );
    match = await _getMatch(a.api, m.u1, m.id);
    expect(match['offeredBy'], m.u2);
    expect(_giveTotal(match, m.u1), 1, reason: 'u1 give must persist (partial update)');
    expect(_giveTotal(match, m.u2), 0, reason: 'cardB leg must be removed by qty 0');
    expect(_isBalanced(match, m.u1, m.u2), isFalse);

    // 3. u1 (non-proposer now) counters to re-add the cardB leg → balanced
    //    again; offeredBy flips back to u1.
    expect(
      await _offer(a, m.id, m.u1, [
        pb.OfferItem(merchId: m.cardB, giverUserId: m.u2, quantity: 1),
      ]),
      200,
    );
    match = await _getMatch(a.api, m.u1, m.id);
    expect(match['offeredBy'], m.u1);
    expect(_isBalanced(match, m.u1, m.u2), isTrue);

    // 4. u2 (non-proposer) accepts the balanced proposal.
    expect(await _setStatus(a, m.id, m.u2, 'ACCEPTED'), 200);
    expect((await _getMatch(a.api, m.u1, m.id))['status'], 'ACCEPTED');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('three offer modes produce the expected legs (#297)', () async {
    final a = _newApi();

    // give-only: u1 proposes only their own give. Legs: giver=u1 only.
    final mg = await _provisionPendingMatch(a.api, tag: 'mode-give');
    expect(
      await _offer(a, mg.id, mg.u1, [
        pb.OfferItem(merchId: mg.cardA, giverUserId: mg.u1, quantity: 1),
      ]),
      200,
    );
    var match = await _getMatch(a.api, mg.u1, mg.id);
    expect(match['offeredBy'], mg.u1);
    expect(_giveTotal(match, mg.u1), 1);
    expect(_giveTotal(match, mg.u2), 0, reason: 'give-only must not add a receive leg');

    // receive-only: u1 proposes only their receive (= u2's give). Legs:
    // giver=u2 only; u1 gives nothing.
    final mr = await _provisionPendingMatch(a.api, tag: 'mode-recv');
    expect(
      await _offer(a, mr.id, mr.u1, [
        pb.OfferItem(merchId: mr.cardB, giverUserId: mr.u2, quantity: 1),
      ]),
      200,
    );
    match = await _getMatch(a.api, mr.u1, mr.id);
    expect(match['offeredBy'], mr.u1);
    expect(_giveTotal(match, mr.u1), 0, reason: 'receive-only must not add a give leg');
    expect(_giveTotal(match, mr.u2), 1);

    // both: u1 proposes give + receive. Balanced; the non-proposer accepts.
    final mb = await _provisionPendingMatch(a.api, tag: 'mode-both');
    expect(
      await _offer(a, mb.id, mb.u1, [
        pb.OfferItem(merchId: mb.cardA, giverUserId: mb.u1, quantity: 1),
        pb.OfferItem(merchId: mb.cardB, giverUserId: mb.u2, quantity: 1),
      ]),
      200,
    );
    match = await _getMatch(a.api, mb.u1, mb.id);
    expect(_isBalanced(match, mb.u1, mb.u2), isTrue);
    expect(await _setStatus(a, mb.id, mb.u2, 'ACCEPTED'), 200);
    expect((await _getMatch(a.api, mb.u1, mb.id))['status'], 'ACCEPTED');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('reject from PENDING and from OFFERED is terminal (#297)', () async {
    final a = _newApi();
    // Note: the user match listing (`GET /matches/user/{id}`) excludes
    // REJECTED matches (`AND status != 'REJECTED'`), so a rejected match
    // is not readable via that endpoint. We instead prove the REJECTED
    // transition took effect by asserting the state machine is terminal:
    // a re-offer on the rejected match is rejected with 400 ("Can only
    // propose on PENDING or OFFERED matches"). The leg-clearing on reject
    // is covered by the backend integration test
    // (`test_trade_negotiation_counter_offer_and_balance`'s reject arm
    // and `test_match_delete_match_items_removes_all`).

    // PENDING → REJECTED. Either party may reject.
    final m1 = await _provisionPendingMatch(a.api, tag: 'reject-pending');
    expect(await _setStatus(a, m1.id, m1.u1, 'REJECTED'), 200);
    // Terminal: the rejected match no longer accepts a proposal.
    expect(
      await _offer(a, m1.id, m1.u2, [
        pb.OfferItem(merchId: m1.cardB, giverUserId: m1.u2, quantity: 1),
      ]),
      400,
    );

    // OFFERED → REJECTED. Open first, then the other party rejects.
    final m2 = await _provisionPendingMatch(a.api, tag: 'reject-offered');
    expect(
      await _offer(a, m2.id, m2.u1, [
        pb.OfferItem(merchId: m2.cardA, giverUserId: m2.u1, quantity: 1),
        pb.OfferItem(merchId: m2.cardB, giverUserId: m2.u2, quantity: 1),
      ]),
      200,
    );
    expect((await _getMatch(a.api, m2.u1, m2.id))['status'], 'OFFERED');
    expect(await _setStatus(a, m2.id, m2.u2, 'REJECTED'), 200);
    // Terminal: re-offer on the rejected match is rejected with 400.
    expect(
      await _offer(a, m2.id, m2.u2, [
        pb.OfferItem(merchId: m2.cardB, giverUserId: m2.u2, quantity: 1),
      ]),
      400,
    );
    // And a status transition out of REJECTED is also rejected with 400
    // ("Can only accept OFFERED matches" / reject-source guard).
    expect(await _setStatus(a, m2.id, m2.u1, 'ACCEPTED'), 400);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('per-leg want-quantity cap (#294) is enforced on propose via the wire (#297)', () async {
    final a = _newApi();
    // u1 TRADEs cardA x2, but u2 only WANTs cardA x1 → the cap on a
    // give-of-A leg is 1. Offering 2 must be rejected with 400 and the
    // match must stay PENDING.
    final m = await _provisionPendingMatch(a.api, tag: 'cap', u1TradeAQty: 2, u2WantAQty: 1);

    expect(
      await _offer(a, m.id, m.u1, [
        pb.OfferItem(merchId: m.cardA, giverUserId: m.u1, quantity: 2),
      ]),
      400,
      reason: 'offering 2 when the receiver wants 1 must exceed the cap',
    );
    // The match is untouched: still PENDING, no legs recorded.
    final match = await _getMatch(a.api, m.u1, m.id);
    expect(match['status'], 'PENDING');
    expect(_giveTotal(match, m.u1) + _giveTotal(match, m.u2), 0);

    // Offering 1 (within the cap) succeeds.
    expect(
      await _offer(a, m.id, m.u1, [
        pb.OfferItem(merchId: m.cardA, giverUserId: m.u1, quantity: 1),
      ]),
      200,
    );
    expect((await _getMatch(a.api, m.u1, m.id))['status'], 'OFFERED');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('accept re-validates the full leg set against current want (#297 cap-at-accept)', () async {
    final a = _newApi();
    // WANT x2 on both sides so a 2:2 balanced proposal fits the cap
    // initially. u1 TRADE A x2 / WANT B x2; u2 TRADE B x2 / WANT A x2.
    final m = await _provisionPendingMatch(
      a.api,
      tag: 'cap-accept',
      u1TradeAQty: 2,
      u1WantBQty: 2,
      u2TradeBQty: 2,
      u2WantAQty: 2,
    );

    // 1. u1 opens a balanced 2:2 proposal: give A x2 (giver=u1) + receive
    //    B x2 (giver=u2). Both legs within cap (WANT x2). -> OFFERED.
    expect(
      await _offer(a, m.id, m.u1, [
        pb.OfferItem(merchId: m.cardA, giverUserId: m.u1, quantity: 2),
        pb.OfferItem(merchId: m.cardB, giverUserId: m.u2, quantity: 2),
      ]),
      200,
    );

    // 2. u2 lowers their WANT of cardA from 2 to 1. u1's persisted
    //    give-of-A x2 leg now exceeds the receiver's WANT (1). The
    //    proposal is still balanced (2:2), so only the cap gate should
    //    block accept — proving accept re-validates the full set, not
    //    just balance.
    await _setInventory(a.api, userId: m.u2, merchId: m.cardA, status: 'WANT', quantity: 1);
    expect(await _setStatus(a, m.id, m.u2, 'ACCEPTED'), 400,
        reason: 'balanced but over-cap after WANT lowered must be rejected at accept');

    // 3. u2 counters the legs down to 1:1 (the A leg is giver=u1, the
    //    editor's receive; the B leg is giver=u2). Now balanced and within
    //    the new cap. -> OFFERED, offeredBy=u2.
    expect(
      await _offer(a, m.id, m.u2, [
        pb.OfferItem(merchId: m.cardA, giverUserId: m.u1, quantity: 1),
        pb.OfferItem(merchId: m.cardB, giverUserId: m.u2, quantity: 1),
      ]),
      200,
    );
    // 4. u1 (non-proposer now) accepts the within-cap balanced proposal.
    expect(await _setStatus(a, m.id, m.u1, 'ACCEPTED'), 200);
    expect((await _getMatch(a.api, m.u1, m.id))['status'], 'ACCEPTED');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('non-participant is forbidden from proposing and accepting (#297 authz)', () async {
    final a = _newApi();
    final m = await _provisionPendingMatch(a.api, tag: 'authz');
    // A third user who is not part of this match.
    final outsider = await _guestLogin(a.api, tag: 'authz_outsider');
    expect(outsider, isNot(m.u1));
    expect(outsider, isNot(m.u2));

    // Outsider cannot open a proposal (legs are valid here — giver=u1 —
    // so the only thing that rejects is the participation check → 403).
    expect(
      await _offer(a, m.id, outsider, [
        pb.OfferItem(merchId: m.cardA, giverUserId: m.u1, quantity: 1),
      ]),
      403,
    );

    // A participant opens, moving the match to OFFERED.
    expect(
      await _offer(a, m.id, m.u1, [
        pb.OfferItem(merchId: m.cardA, giverUserId: m.u1, quantity: 1),
        pb.OfferItem(merchId: m.cardB, giverUserId: m.u2, quantity: 1),
      ]),
      200,
    );
    expect((await _getMatch(a.api, m.u1, m.id))['status'], 'OFFERED');

    // Outsider cannot accept someone else's match → 403 (not 400).
    expect(await _setStatus(a, m.id, outsider, 'ACCEPTED'), 403);

    // The actual non-proposer still can.
    expect(await _setStatus(a, m.id, m.u2, 'ACCEPTED'), 200);
    expect((await _getMatch(a.api, m.u1, m.id))['status'], 'ACCEPTED');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('full happy path: open → accept → complete → apply inventory for both sides (#297)', () async {
    final a = _newApi();
    final m = await _provisionPendingMatch(a.api, tag: 'happy');

    expect(
      await _offer(a, m.id, m.u1, [
        pb.OfferItem(merchId: m.cardA, giverUserId: m.u1, quantity: 1),
        pb.OfferItem(merchId: m.cardB, giverUserId: m.u2, quantity: 1),
      ]),
      200,
    );
    expect((await _getMatch(a.api, m.u1, m.id))['status'], 'OFFERED');

    // Non-proposer accepts the balanced proposal.
    expect(await _setStatus(a, m.id, m.u2, 'ACCEPTED'), 200);
    expect((await _getMatch(a.api, m.u1, m.id))['status'], 'ACCEPTED');

    // Either party completes.
    expect(await _setStatus(a, m.id, m.u1, 'COMPLETED'), 200);
    expect((await _getMatch(a.api, m.u1, m.id))['status'], 'COMPLETED');

    // Apply inventory independently per side; the per-user
    // `inventoryApplied` flag is scoped to the requesting user, so read
    // the match as each participant.
    expect(await _applyInventory(a, m.id, m.u1), 200);
    expect((await _getMatch(a.api, m.u1, m.id))['inventoryApplied'], isTrue);
    // u1 cannot apply twice (idempotency guard) → 409.
    expect(await _applyInventory(a, m.id, m.u1), 409);

    expect(await _applyInventory(a, m.id, m.u2), 200);
    expect((await _getMatch(a.api, m.u2, m.id))['inventoryApplied'], isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}