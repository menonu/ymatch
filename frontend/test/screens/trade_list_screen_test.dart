import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/screens/trade_list_screen.dart';

/// Wraps [child] with the localization delegates so screens that call
/// `AppLocalizations.of(context)` resolve strings in widget tests.
Widget _localized(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

InventoryItem _item(int merchId, String name, int qty, int userId) =>
    InventoryItem()
      ..merchId = merchId
      ..merchName = name
      ..quantity = qty
      ..userId = userId
      ..status = 'HAVE';

InventoryItem _itemWithContext(
  int merchId,
  String name,
  int qty,
  int userId, {
  String? eventName,
  String? groupName,
}) =>
    _item(merchId, name, qty, userId)
      ..eventName = eventName ?? ''
      ..groupName = groupName ?? '';

TradeMatch _pendingMatch() => TradeMatch()
  ..id = 100
  ..user1Id = 1
  ..user2Id = 2
  ..status = 'PENDING'
  ..userHaves.add(_item(10, 'Give Pen', 3, 1))
  ..userWants.add(_item(20, 'Recv Notebook', 2, 2));

void main() {
  testWidgets(
    'offer dialog shows no mode switcher and both sections (#303)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => MockAuthController(_user())),
            matchesProvider(1).overrideWith((ref) async => [_pendingMatch()]),
            notificationCountsProvider(1).overrideWith(
              (ref) async => NotificationCounts(),
            ),
          ],
          child: _localized(const TradeListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // The Match tab (default) lists PENDING matches; open the offer dialog.
      await tester.tap(find.text('Make Offer'));
      await tester.pumpAndSettle();

      // The 3-mode SegmentedButton is gone (#303).
      expect(find.byType(SegmentedButton), findsNothing);

      // A plain-language balance explanation is shown.
      expect(
        find.text(
          'A trade can be completed when the number of items you give and '
          'receive are balanced.',
        ),
        findsOneWidget,
      );

      // Both give and receive sections are always visible (no mode toggle).
      expect(find.text('Items you give:'), findsOneWidget);
      expect(find.text('Items you receive:'), findsOneWidget);
    },
  );

  testWidgets(
    'offer dialog shows the Japanese balance explanation under ja locale (#303)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => MockAuthController(_user())),
            matchesProvider(1).overrideWith((ref) async => [_pendingMatch()]),
            notificationCountsProvider(1).overrideWith(
              (ref) async => NotificationCounts(),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('ja'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TradeListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // "オファーを作成" is the ja makeOffer label.
      await tester.tap(find.text('オファーを作成'));
      await tester.pumpAndSettle();

      expect(find.byType(SegmentedButton), findsNothing);
      expect(
        find.text('渡す数と受け取る数が釣り合っていれば、取引できます。'),
        findsOneWidget,
      );

      // Both sections always visible under ja too (parity with the EN test).
      expect(find.text('渡すアイテム:'), findsOneWidget);
      expect(find.text('受け取るアイテム:'), findsOneWidget);
    },
  );

  testWidgets(
    'match card shows a "Message" text button instead of a chat icon (#310)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => MockAuthController(_user())),
            matchesProvider(1).overrideWith((ref) async => [_pendingMatch()]),
            notificationCountsProvider(1).overrideWith(
              (ref) async => NotificationCounts(),
            ),
          ],
          child: _localized(const TradeListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // The affordance is now an explicit labeled button, not an icon.
      expect(find.text('Message'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
    },
  );

  testWidgets(
    'match card shows the "メッセージ" button under ja locale (#310)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => MockAuthController(_user())),
            matchesProvider(1).overrideWith((ref) async => [_pendingMatch()]),
            notificationCountsProvider(1).overrideWith(
                  (ref) async => NotificationCounts(),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('ja'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TradeListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('メッセージ'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
    },
  );

  testWidgets(
    'match card shows event:group context next to each item (#322)',
        (WidgetTester tester) async {
      final match = TradeMatch()
        ..id = 200
        ..user1Id = 1
        ..user2Id = 2
        ..status = 'PENDING'
        ..userHaves.add(
          _itemWithContext(10, 'Pikachu', 2, 1,
              eventName: 'TokyoFest', groupName: 'BoosterBox'),
        )
        ..userWants.add(
          _itemWithContext(20, 'Charizard', 1, 2,
              eventName: 'OsakaCon', groupName: 'Promos'),
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => MockAuthController(_user())),
            matchesProvider(1).overrideWith((ref) async => [match]),
            notificationCountsProvider(1).overrideWith(
                  (ref) async => NotificationCounts(),
            ),
          ],
          child: _localized(const TradeListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Each item chip renders its event:group context as a second line.
      expect(find.text('TokyoFest: BoosterBox'), findsOneWidget);
      expect(find.text('OsakaCon: Promos'), findsOneWidget);
    },
  );

  testWidgets(
    'match card hides context when neither event nor group is set (#322)',
        (WidgetTester tester) async {
      // No event/group → no context line and no empty ":" placeholder.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => MockAuthController(_user())),
            matchesProvider(1).overrideWith((ref) async => [_pendingMatch()]),
            notificationCountsProvider(1).overrideWith(
                  (ref) async => NotificationCounts(),
            ),
          ],
          child: _localized(const TradeListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // "_pendingMatch" items have no event/group; verify no bare separator
      // leaks through. The item name + qty still render.
      expect(find.text('Give Pen ×3'), findsOneWidget);
      expect(find.text(': '), findsNothing);
    },
  );
}

User _user() => User()..id = 1..username = 'me';

class MockAuthController extends StateNotifier<AsyncValue<User?>>
    implements AuthController {
  MockAuthController(User user) : super(AsyncValue.data(user));

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
  // TODO: implement client
  get client => throw UnimplementedError();
}
