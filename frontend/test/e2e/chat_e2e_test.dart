// Part of #230: comprehensive E2E coverage for all user-facing
// features. This file covers the Chat area — the endpoints that
// drive the match conversation:
//   - GET  /api/v1/matches/{id}/messages  (messagesProvider in chat_screen.dart)
//   - POST /api/v1/matches/{id}/messages  (screen-level call in chat_screen.dart)
//
// The POST endpoint is not wrapped in a Riverpod controller — it is
// called directly from `chat_screen.dart` with a hand-built
// camelCase body. This test sends the same body shape the screen
// sends so a regression like #227 is caught here.
//
// Chat requires an existing match, so setUpAll creates two users,
// two merch items, a cross-trade inventory setup, and waits for the
// auto-matcher to produce a PENDING match (same pattern as
// matches_e2e_test.dart).

@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/chat_screen.dart';
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
      'uuid': 'e2e_chat_u1_${DateTime.now().microsecondsSinceEpoch}',
      'deviceToken': 'e2e-chat',
    });
    user1Id = (u1 as Map)['id'] as int;

    final u2 = await api.post('/api/v1/auth/guest', {
      'uuid': 'e2e_chat_u2_${DateTime.now().microsecondsSinceEpoch}',
      'deviceToken': 'e2e-chat',
    });
    user2Id = (u2 as Map)['id'] as int;
    expect(user2Id, isNot(user1Id));

    final e = await api.post('/api/v1/events', {
      'name': 'E2E chat event',
      'creatorId': user1Id,
    });
    eventId = (e as Map)['id'] as int;

    Future<int> createMerch(String tag) async {
      final r = await api.post('/api/v1/events/$eventId/merch', {
        'name': _uniqueName('e2e_chat_$tag'),
        'creatorId': user1Id,
        'groupName': 'e2e-chat',
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

  test(
      'messagesProvider GETs /matches/{id}/messages and returns a list',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final messages =
        await container.read(messagesProvider(matchId).future);
    expect(messages, isA<List>(),
        reason: 'messagesProvider should return a list for the match');
  });

  test(
      'chat screen POSTs to /matches/{id}/messages with the same body shape',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final content = 'e2e_chat_${DateTime.now().microsecondsSinceEpoch}';

    // Send the exact body shape chat_screen.dart uses.
    await api.post('/api/v1/matches/$matchId/messages', {
      'matchId': matchId,
      'senderId': user1Id,
      'content': content,
    });

    // Verify the message appears via the provider (the same GET path
    // the screen polls every 3 seconds).
    final messages = await container.read(messagesProvider(matchId).future);
    final sent = messages
        .where((m) => m.senderId == user1Id && m.content == content)
        .toList();
    expect(sent, hasLength(1),
        reason: 'the sent message should be visible via messagesProvider');
  });
}
