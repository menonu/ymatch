// Widget tests for ChatScreen (#454).
//
// Covers empty/error message states, message list rendering (own vs peer,
// SYSTEM notices), send empty/non-empty behavior, failed-send SnackBar, and
// the location affordance. Provider overrides + MockClient only.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/screens/chat_screen.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget _localized(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

User _user({int id = 1, String username = 'me'}) => User()
  ..id = id
  ..username = username;

class _MockAuthController extends StateNotifier<AsyncValue<User?>>
    implements AuthController {
  _MockAuthController(User? user) : super(AsyncValue.data(user));

  @override
  Future<void> checkLogin() async {}

  @override
  Future<void> startGuestSession() async {}

  @override
  Future<void> guestLogin(String uuid) async {}

  @override
  Future<void> restoreAccount(String uuid) async {}

  @override
  Future<void> login(String username, String password) async {}

  @override
  Future<void> signup(String username, String password) async {}

  @override
  void logout() {}

  @override
  Future<void> updateUsername(int userId, String newUsername) async {}

  @override
  get client => throw UnimplementedError();
}

ApiClient _client(MockClientHandler handler) {
  final config = ConfigService()..setBaseUrlForTest('http://localhost:3000');
  return ApiClient(config, client: MockClient(handler));
}

Message _msg({
  required int id,
  required int senderId,
  required String content,
  String? messageType,
}) {
  final m = Message()
    ..id = id
    ..matchId = 42
    ..senderId = senderId
    ..content = content;
  if (messageType != null) m.messageType = messageType;
  return m;
}

void main() {
  testWidgets('null user shows loading spinner (#454)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthController(null)),
          apiClientProvider.overrideWithValue(
            _client((_) async => http.Response('[]', 200)),
          ),
          messagesProvider(42).overrideWith((ref) async => const <Message>[]),
        ],
        child: _localized(const ChatScreen(matchId: 42)),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Type a message...'), findsNothing);
  });

  testWidgets('empty messages shows no-messages copy (#454)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthController(_user())),
          apiClientProvider.overrideWithValue(
            _client((_) async => http.Response('[]', 200)),
          ),
          messagesProvider(42).overrideWith((ref) async => const <Message>[]),
        ],
        child: _localized(const ChatScreen(matchId: 42)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No messages yet. Say hello!'), findsOneWidget);
    expect(find.text('Type a message...'), findsOneWidget);
    // Location affordance is always present in the composer row.
    expect(find.byIcon(Icons.add_location_alt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
  });

  testWidgets(
    'message list renders own, peer, SYSTEM, and map-link rows (#454)',
    (tester) async {
      final messages = [
        _msg(id: 1, senderId: 2, content: 'hello from peer'),
        _msg(id: 2, senderId: 1, content: 'hello from me'),
        _msg(
          id: 3,
          senderId: 0,
          content: 'MERCH_DELETED',
          messageType: 'SYSTEM',
        ),
        _msg(
          id: 4,
          senderId: 2,
          content: 'https://www.google.com/maps/search/?api=1&query=35.0,139.0',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            apiClientProvider.overrideWithValue(
              _client((_) async => http.Response('[]', 200)),
            ),
            messagesProvider(42).overrideWith((ref) async => messages),
          ],
          child: _localized(const ChatScreen(matchId: 42)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('hello from peer'), findsOneWidget);
      expect(find.text('hello from me'), findsOneWidget);

      // Own vs peer layout: peer left, own right.
      Align peerAlign = tester.widget<Align>(
        find
            .ancestor(
              of: find.text('hello from peer'),
              matching: find.byType(Align),
            )
            .first,
      );
      Align ownAlign = tester.widget<Align>(
        find
            .ancestor(
              of: find.text('hello from me'),
              matching: find.byType(Align),
            )
            .first,
      );
      expect(peerAlign.alignment, Alignment.centerLeft);
      expect(ownAlign.alignment, Alignment.centerRight);

      // SYSTEM reason code is localized, not shown raw.
      expect(find.text('MERCH_DELETED'), findsNothing);
      expect(
        find.text(
          'This match was cancelled because a traded item was deleted.',
        ),
        findsOneWidget,
      );
      expect(find.text('Open in Maps'), findsOneWidget);
    },
  );

  testWidgets('messagesProvider error shows error prefix (#454)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthController(_user())),
          apiClientProvider.overrideWithValue(
            _client((_) async => http.Response('[]', 200)),
          ),
          messagesProvider(42).overrideWith((ref) async {
            throw Exception('chat unavailable');
          }),
        ],
        child: _localized(const ChatScreen(matchId: 42)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Error:'), findsOneWidget);
    expect(find.textContaining('chat unavailable'), findsOneWidget);
    // Composer still available under the error body.
    expect(find.byIcon(Icons.send), findsOneWidget);
  });

  testWidgets(
    'empty send is a no-op; non-empty send POSTs message body (#454)',
    (tester) async {
      final postedBodies = <Map<String, dynamic>>[];
      final api = _client((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/matches/42/messages') {
          postedBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{}', 200);
        }
        if (request.method == 'GET' &&
            request.url.path == '/api/v1/matches/42/messages') {
          return http.Response('[]', 200);
        }
        return http.Response('[]', 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            apiClientProvider.overrideWithValue(api),
            // Leave messagesProvider un-overridden so send invalidation
            // re-fetches via MockClient.
          ],
          child: _localized(const ChatScreen(matchId: 42)),
        ),
      );
      await tester.pumpAndSettle();

      // Empty composer → send is a no-op.
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(postedBodies, isEmpty);

      await tester.enterText(find.byType(TextField), '  hi there  ');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(postedBodies, hasLength(1));
      expect(postedBodies.single['matchId'], 42);
      expect(postedBodies.single['senderId'], 1);
      expect(postedBodies.single['content'], 'hi there');
      // Composer is cleared after send.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '',
      );
    },
  );

  testWidgets('failed send shows failedToSend snackbar (#454 / #245)', (
    tester,
  ) async {
    final api = _client((request) async {
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/matches/42/messages') {
        return http.Response('rejected', 422);
      }
      return http.Response('[]', 200);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthController(_user())),
          apiClientProvider.overrideWithValue(api),
        ],
        child: _localized(const ChatScreen(matchId: 42)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'will fail');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to send:'), findsOneWidget);
  });

  testWidgets(
    'location affordance IconButton is enabled next to composer (#454)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            apiClientProvider.overrideWithValue(
              _client((_) async => http.Response('[]', 200)),
            ),
            messagesProvider(42).overrideWith((ref) async => const <Message>[]),
          ],
          child: _localized(const ChatScreen(matchId: 42)),
        ),
      );
      await tester.pumpAndSettle();

      final locationButton = find.byIcon(Icons.add_location_alt_outlined);
      expect(locationButton, findsOneWidget);
      // onPressed is non-null (enabled). MapPicker navigation is covered by
      // map_picker_screen_test.dart; avoid opening the map here (tile network).
      final iconButton = tester.widget<IconButton>(
        find.ancestor(of: locationButton, matching: find.byType(IconButton)),
      );
      expect(iconButton.onPressed, isNotNull);
    },
  );
}
