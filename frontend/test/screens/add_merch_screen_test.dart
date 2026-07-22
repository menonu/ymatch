// Widget tests for AddMerchScreen (#454, #466).
//
// Covers create-flow happy path, validation, failure, empty/error states, and
// group chip display_name resolution. Uses provider overrides + MockClient —
// no live backend.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/screens/add_merch_screen.dart';
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

User _user() => User()
  ..id = 1
  ..username = 'me';

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

ApiClient _emptyGetClient() =>
    _client((request) async => http.Response('[]', 200));

Merchandise _merch({
  required String groupName,
  String name = 'Item A',
  int id = 10,
}) => Merchandise()
  ..id = id
  ..eventId = 5
  ..name = name
  ..groupName = groupName
  ..creatorId = 1;

MerchandiseGroup _group({required String name, String? displayName}) {
  final g = MerchandiseGroup()
    ..id = 1
    ..eventId = 5
    ..groupName = name;
  if (displayName != null) g.displayName = displayName;
  return g;
}

List<Override> _baseOverrides({
  required List<Merchandise> merch,
  List<MerchandiseGroup>? groups,
  ApiClient? api,
  User? user,
}) {
  final eventId = 5;
  return [
    authProvider.overrideWith((ref) => _MockAuthController(user ?? _user())),
    apiClientProvider.overrideWithValue(api ?? _emptyGetClient()),
    merchProvider(eventId).overrideWith((ref) async => merch),
    eventGroupsProvider(
      eventId,
    ).overrideWith((ref) async => groups ?? const <MerchandiseGroup>[]),
  ];
}

void main() {
  testWidgets(
    'Add Merch chips and header show display_name, not the key (#466)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(
            merch: [_merch(groupName: 'Pins')],
            groups: [_group(name: 'Pins', displayName: 'Enamel Pins!')],
          ),
          child: _localized(const AddMerchScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      // Chip label uses the cosmetic name.
      expect(find.text('Enamel Pins!'), findsWidgets);
      // Internal key must not appear as the chip/header label.
      expect(find.text('Pins'), findsNothing);
      // Header: Existing items in "Enamel Pins!"
      expect(find.textContaining('Enamel Pins!'), findsWidgets);
    },
  );

  testWidgets(
    'Add Merch falls back to group_name when display_name unset (#466)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(
            merch: [_merch(groupName: 'Stickers')],
            groups: [_group(name: 'Stickers')],
          ),
          child: _localized(const AddMerchScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stickers'), findsWidgets);
    },
  );

  testWidgets(
    'create flow happy path posts merch and shows success snackbar (#454)',
    (tester) async {
      final postedBodies = <Map<String, dynamic>>[];
      final api = _client((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/events/5/merch') {
          postedBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{}', 200);
        }
        return http.Response('[]', 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(
            merch: [_merch(groupName: 'Pins', name: 'Existing Pin')],
            groups: [_group(name: 'Pins')],
            api: api,
          ),
          child: _localized(const AddMerchScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      // Group is auto-selected; existing preview is visible.
      expect(find.text('Existing Pin'), findsOneWidget);
      expect(find.text('Add Item'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'New Pin');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Item'));
      await tester.pumpAndSettle();

      expect(postedBodies, hasLength(1));
      expect(postedBodies.single['name'], 'New Pin');
      expect(postedBodies.single['groupName'], 'Pins');
      expect(postedBodies.single['creatorId'], 1);
      expect(find.text('Added "New Pin" successfully.'), findsOneWidget);
      // Name field is cleared for continuous adding.
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        '',
      );
    },
  );

  testWidgets('empty name is a no-op (no POST, no snackbar) (#454)', (
    tester,
  ) async {
    var postCount = 0;
    final api = _client((request) async {
      if (request.method == 'POST') {
        postCount++;
        return http.Response('{}', 200);
      }
      return http.Response('[]', 200);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: _baseOverrides(
          merch: [_merch(groupName: 'Pins')],
          groups: [_group(name: 'Pins')],
          api: api,
        ),
        child: _localized(const AddMerchScreen(eventId: 5)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Item'));
    await tester.pumpAndSettle();

    expect(postCount, 0);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'submit without a selected group shows select-group snackbar (#454)',
    (tester) async {
      var postCount = 0;
      final api = _client((request) async {
        if (request.method == 'POST') {
          postCount++;
          return http.Response('{}', 200);
        }
        return http.Response('[]', 200);
      });

      // Empty merch + empty groups → no auto-selected group.
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(
            merch: const [],
            groups: const [],
            api: api,
          ),
          child: _localized(const AddMerchScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No items in this group yet.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Orphan Item');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Item'));
      await tester.pumpAndSettle();

      expect(postCount, 0);
      expect(
        find.text('Please select or create an item group first.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('add failure surfaces failedToAdd snackbar (#454 / #227)', (
    tester,
  ) async {
    final api = _client((request) async {
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/events/5/merch') {
        return http.Response('duplicate name', 422);
      }
      return http.Response('[]', 200);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: _baseOverrides(
          merch: [_merch(groupName: 'Pins')],
          groups: [_group(name: 'Pins')],
          api: api,
        ),
        child: _localized(const AddMerchScreen(eventId: 5)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Dup Pin');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Item'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to add "Dup Pin"'), findsOneWidget);
    expect(find.textContaining('Added "Dup Pin" successfully.'), findsNothing);
  });

  testWidgets('merchProvider error shows error prefix (#454)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthController(_user())),
          apiClientProvider.overrideWithValue(_emptyGetClient()),
          merchProvider(5).overrideWith((ref) async {
            throw Exception('network down');
          }),
          eventGroupsProvider(5).overrideWith((ref) async => const []),
        ],
        child: _localized(const AddMerchScreen(eventId: 5)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Error:'), findsOneWidget);
    expect(find.textContaining('network down'), findsOneWidget);
    expect(find.text('Add Item'), findsNothing);
  });

  testWidgets('preview lists only items in the selected group (#454)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _baseOverrides(
          merch: [
            _merch(groupName: 'Pins', name: 'Pin One', id: 1),
            _merch(groupName: 'Pins', name: 'Pin Two', id: 2),
            _merch(groupName: 'Stickers', name: 'Sticker One', id: 3),
          ],
          groups: [
            _group(name: 'Pins'),
            _group(name: 'Stickers'),
          ],
        ),
        child: _localized(const AddMerchScreen(eventId: 5)),
      ),
    );
    await tester.pumpAndSettle();

    // Natural sort puts Pins first; auto-selects Pins.
    expect(find.text('Pin One'), findsOneWidget);
    expect(find.text('Pin Two'), findsOneWidget);
    expect(find.text('Sticker One'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Stickers'));
    await tester.pumpAndSettle();

    expect(find.text('Sticker One'), findsOneWidget);
    expect(find.text('Pin One'), findsNothing);
    expect(find.text('Pin Two'), findsNothing);
  });
}
