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

TradeMatch _pendingMatch() => TradeMatch()
  ..id = 100
  ..user1Id = 1
  ..user2Id = 2
  ..status = 'PENDING'
  ..userHaves.add(_item(10, 'Give Pen', 3, 1))
  ..userWants.add(_item(20, 'Recv Notebook', 2, 2));

InventoryItem _itemWithCtx(
  int merchId,
  String name,
  int qty,
  int userId, {
  String? event,
  String? group,
}) {
  final item = InventoryItem()
    ..merchId = merchId
    ..merchName = name
    ..quantity = qty
    ..userId = userId
    ..status = 'HAVE';
  if (event != null) item.eventName = event;
  if (group != null) item.groupName = group;
  return item;
}

// Match whose haves/wants carry event:group context (#322).
TradeMatch _ctxMatch() => TradeMatch()
  ..id = 101
  ..user1Id = 1
  ..user2Id = 2
  ..status = 'PENDING'
  ..userHaves.add(
    _itemWithCtx(10, 'Give Pen', 3, 1, event: 'TokyoFest', group: 'BoosterBox'),
  )
  ..userWants.add(
    _itemWithCtx(20, 'Recv Notebook', 2, 2, event: 'TokyoFest', group: 'BoosterBox'),
  );

// Match whose item has no event/group — must render with no separator.
TradeMatch _noCtxMatch() => TradeMatch()
  ..id = 102
  ..user1Id = 1
  ..user2Id = 2
  ..status = 'PENDING'
  ..userHaves.add(_itemWithCtx(11, 'Loose Card', 1, 1));

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
    'match card "Message" affordance is a filled button, not bare text '
    '(#310 follow-up)',
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

      // The Message affordance must read as a button — a filled (tonal)
      // background — not a borderless TextButton that looks like a link.
      expect(
        find.ancestor(
          of: find.text('Message'),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.text('Message'),
          matching: find.byType(TextButton),
        ),
        findsNothing,
      );
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
    'match screen AppBar has a reload button that refetches matches (#335)',
    (WidgetTester tester) async {
      int matchFetchCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => MockAuthController(_user())),
            // First fetch returns one PENDING match; the reload returns none.
            // This lets us observe both the refetch and the tab-badge update.
            matchesProvider(1).overrideWith((ref) async {
              matchFetchCount++;
              return matchFetchCount == 1 ? [_pendingMatch()] : const [];
            }),
            notificationCountsProvider(1).overrideWith(
              (ref) async => NotificationCounts(),
            ),
          ],
          child: _localized(const TradeListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Initial load fetches the matches once; the Match tab shows a "1" badge.
      expect(matchFetchCount, 1);
      expect(find.text('1'), findsOneWidget);

      // The AppBar shows a refresh/reload icon (parity with the events screen).
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byTooltip('Refresh'), findsOneWidget);

      // Tapping it invalidates the provider, reloading the list and the
      // tab-badge counts (which derive from the matches list).
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(matchFetchCount, 2);
      // The PENDING match is gone on reload, so the Match tab badge is gone.
      expect(find.text('1'), findsNothing);
    },
  );

  testWidgets(
    'item chips show event:group context after the name in en (#322)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => MockAuthController(_user())),
            matchesProvider(1).overrideWith((ref) async => [_ctxMatch()]),
            notificationCountsProvider(1).overrideWith(
              (ref) async => NotificationCounts(),
            ),
          ],
          child: _localized(const TradeListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Give Pen ×3  ·  TokyoFest: BoosterBox'),
        findsOneWidget,
      );
      expect(
        find.text('Recv Notebook ×2  ·  TokyoFest: BoosterBox'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'item chips show localized event：group context under ja (#322)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => MockAuthController(_user())),
            matchesProvider(1).overrideWith((ref) async => [_ctxMatch()]),
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

      // Fullwidth colon under ja.
      expect(
        find.text('Give Pen ×3  ·  TokyoFest：BoosterBox'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'items without event/group render no separator and no empty colon '
    '(#322)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => MockAuthController(_user())),
            matchesProvider(1).overrideWith((ref) async => [_noCtxMatch()]),
            notificationCountsProvider(1).overrideWith(
              (ref) async => NotificationCounts(),
            ),
          ],
          child: _localized(const TradeListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Plain label, no context suffix.
      expect(find.text('Loose Card ×1'), findsOneWidget);
      // No separator dot rendered when neither event nor group is set —
      // i.e. the helper emits no trailing `·` or empty placeholder.
      expect(find.textContaining('·'), findsNothing);
    },
  );

  testWidgets(
    'an empty-string event name is treated as absent — no empty colon '
    '(#322)',
    (WidgetTester tester) async {
      // event_name is set but empty (allowed by the backend, which rejects
      // None but not ""). The helper must fall back to group-only rather than
      // render `: BoosterBox`.
      final match = TradeMatch()
        ..id = 103
        ..user1Id = 1
        ..user2Id = 2
        ..status = 'PENDING'
        ..userHaves
            .add(_itemWithCtx(12, 'Pikachu', 2, 1, event: '', group: 'BoosterBox'));
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

      // Group-only suffix; no empty-left `: ` placeholder.
      expect(find.text('Pikachu ×2  ·  BoosterBox'), findsOneWidget);
      expect(find.textContaining(': '), findsNothing);
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
