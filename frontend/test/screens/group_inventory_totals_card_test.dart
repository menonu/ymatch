// Widget tests for the group inventory totals card (#508).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/screens/event_detail/group_inventory_totals_card.dart';
import 'package:frontend/screens/event_detail/merch_filters.dart';

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  const totals = GroupInventoryTotals(
    totalHave: 4,
    totalWant: 5,
    totalTrade: 2,
  );

  testWidgets('shows Total label and all three counters in all mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const GroupInventoryTotalsCard(
          totals: totals,
          displayMode: InventoryDisplayMode.all,
        ),
      ),
    );

    expect(find.byKey(groupInventoryTotalsCardKey), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    // Short labels: Own=O, Wish=W, For Trade=F
    expect(find.text('O'), findsOneWidget);
    expect(find.text('W'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // Read-only: no stepper controls.
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.remove), findsNothing);
  });

  testWidgets('have mode shows only Own total', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const GroupInventoryTotalsCard(
          totals: totals,
          displayMode: InventoryDisplayMode.have,
        ),
      ),
    );

    expect(find.text('O'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('W'), findsNothing);
    expect(find.text('F'), findsNothing);
    expect(find.text('5'), findsNothing);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('wantTrade mode shows Wish + For Trade only', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const GroupInventoryTotalsCard(
          totals: totals,
          displayMode: InventoryDisplayMode.wantTrade,
        ),
      ),
    );

    expect(find.text('O'), findsNothing);
    expect(find.text('W'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('trade mode shows only For Trade total', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const GroupInventoryTotalsCard(
          totals: totals,
          displayMode: InventoryDisplayMode.trade,
        ),
      ),
    );

    expect(find.text('F'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('O'), findsNothing);
    expect(find.text('W'), findsNothing);
  });

  testWidgets('zeros render without crashing', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const GroupInventoryTotalsCard(
          totals: GroupInventoryTotals.zero,
          displayMode: InventoryDisplayMode.all,
        ),
      ),
    );

    expect(find.byKey(groupInventoryTotalsCardKey), findsOneWidget);
    expect(find.text('0'), findsNWidgets(3));
  });
}
