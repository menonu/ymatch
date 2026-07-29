import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/screens/trade_list/match_balance.dart';
import 'package:frontend/screens/trade_list/match_card.dart';
import 'package:frontend/screens/trade_list/match_status_chrome.dart';
import 'package:frontend/screens/trade_list/trade_tab.dart';

Widget _localized(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

User _user() => User()
  ..id = 1
  ..username = 'alice'
  ..role = 'user';

InventoryItem _item(int merchId, String name, int qty, int userId) =>
    InventoryItem()
      ..merchId = merchId
      ..merchName = name
      ..quantity = qty
      ..userId = userId
      ..status = 'HAVE';

MatchItem _leg({
  required int merchId,
  required String name,
  required int qty,
  required int giverId,
}) => MatchItem()
  ..merchId = merchId
  ..merchName = name
  ..quantity = qty
  ..giverUserId = giverId;

TradeMatch _offeredMatch({required bool balanced}) {
  final match = TradeMatch()
    ..id = 50
    ..user1Id = 1
    ..user2Id = 2
    ..status = 'OFFERED'
    ..offeredBy = 1
    ..otherUser = (User()
      ..id = 2
      ..username = 'bob')
    ..userHaves.add(_item(10, 'Give Pen', 3, 1))
    ..userWants.add(_item(20, 'Recv Notebook', 2, 2));
  match.selectedItems.add(
    _leg(merchId: 10, name: 'Give Pen', qty: balanced ? 2 : 1, giverId: 1),
  );
  match.selectedItems.add(
    _leg(merchId: 20, name: 'Recv Notebook', qty: 2, giverId: 2),
  );
  return match;
}

void main() {
  group('MatchStatusChip', () {
    testWidgets('renders localized labels for lifecycle statuses (#496)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _localized(
          const Column(
            children: [
              MatchStatusChip(status: 'PENDING'),
              MatchStatusChip(status: 'OFFERED'),
              MatchStatusChip(status: 'ACCEPTED'),
              MatchStatusChip(status: 'COMPLETED'),
              MatchStatusChip(status: 'CANCELLED'),
              MatchStatusChip(status: 'WEIRD'),
            ],
          ),
        ),
      );

      expect(find.text('PENDING'), findsOneWidget);
      expect(find.text('OFFERED'), findsOneWidget);
      expect(find.text('ACCEPTED'), findsOneWidget);
      expect(find.text('COMPLETED'), findsOneWidget);
      expect(find.text('CANCELLED'), findsOneWidget);
      // Unknown statuses fall through to the raw string.
      expect(find.text('WEIRD'), findsOneWidget);
    });
  });

  group('PriorHistoryAnnotation', () {
    testWidgets('shows Rejected before for rematched PENDING (#496 / #477)', (
      WidgetTester tester,
    ) async {
      final match = TradeMatch()
        ..id = 1
        ..user1Id = 1
        ..user2Id = 2
        ..status = 'PENDING'
        ..lastTerminalStatus = 'REJECTED'
        ..rematchCount = 1;

      await tester.pumpWidget(_localized(PriorHistoryAnnotation(match: match)));

      expect(find.text('Rejected before'), findsOneWidget);
    });

    testWidgets('appends rematch count when rematchCount > 1', (
      WidgetTester tester,
    ) async {
      final match = TradeMatch()
        ..id = 1
        ..user1Id = 1
        ..user2Id = 2
        ..status = 'PENDING'
        ..lastTerminalStatus = 'CANCELLED'
        ..rematchCount = 2;

      await tester.pumpWidget(_localized(PriorHistoryAnnotation(match: match)));

      expect(find.text('Cancelled before · 2×'), findsOneWidget);
    });
  });

  group('MatchBalanceIndicator', () {
    testWidgets(
      'shows balanced summary for equal positive legs (#496 / #297)',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _localized(const MatchBalanceIndicator(give: 2, receive: 2)),
        );

        expect(find.textContaining('2'), findsWidgets);
        expect(find.text('Balanced'), findsOneWidget);
        expect(find.byIcon(Icons.balance), findsOneWidget);
      },
    );

    testWidgets('shows unbalanced summary when sides differ', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _localized(const MatchBalanceIndicator(give: 1, receive: 2)),
      );

      expect(find.text('Unbalanced'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    test('matchLegTotals / matchIsBalanced pure helpers', () {
      final balanced = _offeredMatch(balanced: true);
      expect(matchLegTotals(1, balanced), (2, 2));
      expect(matchIsBalanced(1, balanced), isTrue);

      final unbalanced = _offeredMatch(balanced: false);
      expect(matchLegTotals(1, unbalanced), (1, 2));
      expect(matchIsBalanced(1, unbalanced), isFalse);
    });
  });

  group('TradeMatchCard', () {
    testWidgets(
      'happy path: status, potential items, Message, Make Offer (#496)',
      (WidgetTester tester) async {
        final match = TradeMatch()
          ..id = 100
          ..user1Id = 1
          ..user2Id = 2
          ..status = 'PENDING'
          ..otherUser = (User()
            ..id = 2
            ..username = 'bob')
          ..userHaves.add(_item(10, 'Give Pen', 3, 1))
          ..userWants.add(_item(20, 'Recv Notebook', 2, 2));

        var offerTapped = false;
        await tester.pumpWidget(
          _localized(
            TradeMatchCard(
              user: _user(),
              match: match,
              tab: TradeTab.match_,
              onOpenChat: () {},
              onUpdateStatus: (_) {},
              onMakeOffer: () => offerTapped = true,
              onApplyInventory: () {},
            ),
          ),
        );

        expect(find.text('bob'), findsOneWidget);
        expect(find.text('PENDING'), findsOneWidget);
        expect(find.text('Give Pen ×3'), findsOneWidget);
        expect(find.text('Recv Notebook ×2'), findsOneWidget);
        expect(find.text('Message'), findsOneWidget);
        expect(find.text('Make Offer'), findsOneWidget);

        await tester.tap(find.text('Make Offer'));
        await tester.pump();
        expect(offerTapped, isTrue);
      },
    );

    testWidgets(
      'OFFERED card shows balance indicator and selected legs (#496)',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _localized(
            TradeMatchCard(
              user: _user(),
              match: _offeredMatch(balanced: true),
              tab: TradeTab.offerOut,
              onOpenChat: () {},
              onUpdateStatus: (_) {},
              onMakeOffer: () {},
              onApplyInventory: () {},
            ),
          ),
        );

        expect(find.text('OFFERED'), findsOneWidget);
        expect(find.text('Balanced'), findsOneWidget);
        expect(find.text('Give Pen ×2'), findsOneWidget);
        expect(find.text('Recv Notebook ×2'), findsOneWidget);
        expect(find.text('Waiting for response...'), findsOneWidget);
      },
    );

    testWidgets(
      'shows event on header and group twice on give/receive rows (#534)',
      (WidgetTester tester) async {
        final match = _offeredMatch(balanced: true)
          ..eventName = 'TokyoFest'
          ..groupName = 'BoosterBox'
          ..groupDisplayName = 'Booster Boxes';

        await tester.pumpWidget(
          _localized(
            TradeMatchCard(
              user: _user(),
              match: match,
              tab: TradeTab.offerOut,
              onOpenChat: () {},
              onUpdateStatus: (_) {},
              onMakeOffer: () {},
              onApplyInventory: () {},
            ),
          ),
        );

        // Event stays on the header with a fixed prefix; combined label is gone.
        expect(find.text('Event: TokyoFest'), findsOneWidget);
        expect(find.text('TokyoFest: Booster Boxes'), findsNothing);
        // Same group label on give and receive (#534).
        expect(find.text('Booster Boxes'), findsNWidgets(2));
        expect(find.text('BoosterBox'), findsNothing);
      },
    );
  });
}
