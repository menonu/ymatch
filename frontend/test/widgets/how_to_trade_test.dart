import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/widgets/how_to_trade.dart';

void main() {
  testWidgets('how-to-trade documents projected parentheses (#427)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: HowToTradeContent()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('number in parentheses'), findsOneWidget);
    expect(find.textContaining('2(1)'), findsOneWidget);
  });
}
