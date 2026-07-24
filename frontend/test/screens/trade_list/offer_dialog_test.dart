import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/screens/trade_list/offer_dialog.dart';

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

TradeMatch _pendingMatch() => TradeMatch()
  ..id = 100
  ..user1Id = 1
  ..user2Id = 2
  ..status = 'PENDING'
  ..userHaves.add(_item(10, 'Give Pen', 3, 1))
  ..userWants.add(_item(20, 'Recv Notebook', 2, 2));

void main() {
  testWidgets(
    'offer dialog happy path: both sections, balance, no mode switcher (#496 / #303)',
    (WidgetTester tester) async {
      List<OfferItem>? submitted;

      await tester.pumpWidget(
        _localized(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showTradeOfferDialog(
                context: context,
                user: _user(),
                match: _pendingMatch(),
                onSubmit: (items) => submitted = items,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The 3-mode SegmentedButton is gone (#303).
      expect(find.byType(SegmentedButton), findsNothing);

      expect(
        find.text(
          'A trade can be completed when the number of items you give and '
          'receive are balanced.',
        ),
        findsOneWidget,
      );
      expect(find.text('Items you give:'), findsOneWidget);
      expect(find.text('Items you receive:'), findsOneWidget);
      expect(find.text('Give Pen'), findsOneWidget);
      expect(find.text('Recv Notebook'), findsOneWidget);
      expect(find.text('Unbalanced'), findsOneWidget);

      // Select both legs at default qty 1 → give 1 / receive 1 → Balanced.
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();

      expect(find.text('Balanced'), findsOneWidget);

      // Submit uses the localized sendOfferItems label (count of qty>0 legs).
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Offer (2 items)'));
      await tester.pumpAndSettle();

      expect(submitted, isNotNull);
      expect(submitted!.length, 2);
      expect(submitted!.map((i) => i.merchId).toSet(), {10, 20});
    },
  );

  testWidgets('offer dialog Japanese balance explanation (#496 / #303)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showTradeOfferDialog(
                context: context,
                user: _user(),
                match: _pendingMatch(),
                onSubmit: (_) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton), findsNothing);
    expect(find.text('渡す数と受け取る数が釣り合っていれば、取引できます。'), findsOneWidget);
    expect(find.text('渡すアイテム:'), findsOneWidget);
    expect(find.text('受け取るアイテム:'), findsOneWidget);
  });
}
