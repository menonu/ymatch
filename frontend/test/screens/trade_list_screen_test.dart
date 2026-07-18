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

void main() {
  testWidgets('offer dialog shows no mode switcher and both sections (#303)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => MockAuthController(_user())),
          matchesProvider(1).overrideWith((ref) async => [_pendingMatch()]),
          notificationCountsProvider(
            1,
          ).overrideWith((ref) async => NotificationCounts()),
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
  });

  testWidgets(
    'offer dialog shows the Japanese balance explanation under ja locale (#303)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => MockAuthController(_user())),
            matchesProvider(1).overrideWith((ref) async => [_pendingMatch()]),
            notificationCountsProvider(
              1,
            ).overrideWith((ref) async => NotificationCounts()),
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
      expect(find.text('渡す数と受け取る数が釣り合っていれば、取引できます。'), findsOneWidget);

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
            notificationCountsProvider(
              1,
            ).overrideWith((ref) async => NotificationCounts()),
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
            notificationCountsProvider(
              1,
            ).overrideWith((ref) async => NotificationCounts()),
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

  testWidgets('match card shows the "メッセージ" button under ja locale (#310)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => MockAuthController(_user())),
          matchesProvider(1).overrideWith((ref) async => [_pendingMatch()]),
          notificationCountsProvider(
            1,
          ).overrideWith((ref) async => NotificationCounts()),
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
  });

  // #314: a completed match stays conversable — the Message button and card
  // tap remain available on the Done tab, just like on the other tabs.
  TradeMatch _completedMatch() => TradeMatch()
    ..id = 200
    ..user1Id = 1
    ..user2Id = 2
    ..status = 'COMPLETED'
    ..inventoryApplied = true
    ..userHaves.add(_item(10, 'Give Pen', 3, 1))
    ..userWants.add(_item(20, 'Recv Notebook', 2, 2));

  testWidgets('completed match card shows the Message button (#314)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => MockAuthController(_user())),
          matchesProvider(1).overrideWith((ref) async => [_completedMatch()]),
          notificationCountsProvider(
            1,
          ).overrideWith((ref) async => NotificationCounts()),
        ],
        child: _localized(const TradeListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to the Done (completed) tab — the only place completed matches
    // surface. Scope the tab text to the TabBar so the finder stays
    // unambiguous even if a future l10n string collides with a card label.
    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('Done')),
    );
    await tester.pumpAndSettle();

    // The Message affordance is present on a completed match too (#314).
    expect(find.text('Message'), findsOneWidget);
  });

  testWidgets('completed match card shows the メッセージ button under ja (#314)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => MockAuthController(_user())),
          matchesProvider(1).overrideWith((ref) async => [_completedMatch()]),
          notificationCountsProvider(
            1,
          ).overrideWith((ref) async => NotificationCounts()),
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

    // Under ja, `tabDone` and `statusCompleted` are both "完了", so scope
    // to the TabBar to avoid matching the status chip on the completed card.
    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('完了')),
    );
    await tester.pumpAndSettle();

    expect(find.text('メッセージ'), findsOneWidget);
  });

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
            notificationCountsProvider(
              1,
            ).overrideWith((ref) async => NotificationCounts()),
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

  // #322 / ADR 0001: a match is scoped to one item group, so the card shows
  // `event:group` once on the header; items render as plain `Name ×qty`.
  TradeMatch _groupMatch() => TradeMatch()
    ..id = 101
    ..user1Id = 1
    ..user2Id = 2
    ..status = 'PENDING'
    ..eventName = 'TokyoFest'
    ..groupName = 'BoosterBox'
    ..userHaves.add(_item(10, 'Give Pen', 3, 1))
    ..userWants.add(_item(20, 'Recv Notebook', 2, 2));

  testWidgets(
    'match card shows event:group on the header and plain item chips (#322)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => MockAuthController(_user())),
            matchesProvider(1).overrideWith((ref) async => [_groupMatch()]),
            notificationCountsProvider(
              1,
            ).overrideWith((ref) async => NotificationCounts()),
          ],
          child: _localized(const TradeListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Card-level context label.
      expect(find.text('TokyoFest: BoosterBox'), findsOneWidget);
      // Items are plain — no per-item `·` suffix.
      expect(find.text('Give Pen ×3'), findsOneWidget);
      expect(find.text('Recv Notebook ×2'), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);
    },
  );

  testWidgets('match card prefers groupDisplayName over groupName (#466)', (
    WidgetTester tester,
  ) async {
    final match = _groupMatch()..groupDisplayName = 'Booster Boxes';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => MockAuthController(_user())),
          matchesProvider(1).overrideWith((ref) async => [match]),
          notificationCountsProvider(
            1,
          ).overrideWith((ref) async => NotificationCounts()),
        ],
        child: _localized(const TradeListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TokyoFest: Booster Boxes'), findsOneWidget);
    expect(find.text('TokyoFest: BoosterBox'), findsNothing);
  });

  testWidgets('match card shows localized event：group under ja (#322)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => MockAuthController(_user())),
          matchesProvider(1).overrideWith((ref) async => [_groupMatch()]),
          notificationCountsProvider(
            1,
          ).overrideWith((ref) async => NotificationCounts()),
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
    expect(find.text('TokyoFest：BoosterBox'), findsOneWidget);
  });

  testWidgets(
    'match card guard: a group without an event renders no label (#322)',
    (WidgetTester tester) async {
      // hasGroupName() && hasEventName() guard: a group-only match (no event)
      // must NOT render the label, so the group name is not shown standalone.
      // Asserting on the specific group name (not a `: ` substring) keeps this
      // robust against future l10n strings that happen to contain a colon.
      final match = TradeMatch()
        ..id = 104
        ..user1Id = 1
        ..user2Id = 2
        ..status = 'PENDING'
        ..groupName = 'BoosterBox'
        ..userHaves.add(_item(10, 'Give Pen', 3, 1));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => MockAuthController(_user())),
            matchesProvider(1).overrideWith((ref) async => [match]),
            notificationCountsProvider(
              1,
            ).overrideWith((ref) async => NotificationCounts()),
          ],
          child: _localized(const TradeListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // No `event:group` label and no standalone group name.
      expect(find.textContaining('BoosterBox'), findsNothing);
      // Items still render plainly.
      expect(find.text('Give Pen ×3'), findsOneWidget);
    },
  );

  testWidgets('CANCELLED matches appear only on Done tab (ADR 0010 / #452)', (
    WidgetTester tester,
  ) async {
    final cancelled = TradeMatch()
      ..id = 999
      ..user1Id = 1
      ..user2Id = 2
      ..status = 'CANCELLED'
      ..userHaves.add(_item(10, 'Gone Pen', 1, 1));
    final pending = _pendingMatch();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => MockAuthController(_user())),
          matchesProvider(1).overrideWith((ref) async => [pending, cancelled]),
          notificationCountsProvider(
            1,
          ).overrideWith((ref) async => NotificationCounts()),
        ],
        child: _localized(const TradeListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Match tab: only the PENDING card; CANCELLED excluded from actionable tabs.
    expect(find.text('Make Offer'), findsOneWidget);
    expect(find.text('Gone Pen'), findsNothing);
    expect(find.textContaining('Give Pen'), findsWidgets);

    // Done tab surfaces CANCELLED for history (ADR 0010).
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('CANCELLED'), findsOneWidget);
    expect(find.textContaining('Gone Pen'), findsOneWidget);
    expect(find.text('Make Offer'), findsNothing);
  });
}

User _user() => User()
  ..id = 1
  ..username = 'me';

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
