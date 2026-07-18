// Widget tests for Add Merch group chips resolving display_name (#466).

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
  _MockAuthController(User user) : super(AsyncValue.data(user));

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

ApiClient _emptyGetClient() {
  final config = ConfigService()..setBaseUrlForTest('http://localhost:3000');
  return ApiClient(
    config,
    client: MockClient((request) async => http.Response('[]', 200)),
  );
}

Merchandise _merch({required String groupName, String name = 'Item A'}) =>
    Merchandise()
      ..id = 10
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

void main() {
  testWidgets(
    'Add Merch chips and header show display_name, not the key (#466)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            apiClientProvider.overrideWithValue(_emptyGetClient()),
            merchProvider(
              5,
            ).overrideWith((ref) async => [_merch(groupName: 'Pins')]),
            eventGroupsProvider(5).overrideWith(
              (ref) async => [
                _group(name: 'Pins', displayName: 'Enamel Pins!'),
              ],
            ),
          ],
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
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(_user())),
            apiClientProvider.overrideWithValue(_emptyGetClient()),
            merchProvider(
              5,
            ).overrideWith((ref) async => [_merch(groupName: 'Stickers')]),
            eventGroupsProvider(
              5,
            ).overrideWith((ref) async => [_group(name: 'Stickers')]),
          ],
          child: _localized(const AddMerchScreen(eventId: 5)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stickers'), findsWidgets);
    },
  );
}
