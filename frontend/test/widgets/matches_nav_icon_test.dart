import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/matches_nav_icon.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('no badges when both counts are 0 (#535)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const MatchesNavIcon(
          icon: Icons.swap_horiz,
          matchCount: 0,
          unreadMessageCount: 0,
        ),
      ),
    );

    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d+$')), findsNothing);
  });

  testWidgets('red match count only when matchCount > 0 (#535)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const MatchesNavIcon(
          icon: Icons.swap_horiz,
          matchCount: 3,
          unreadMessageCount: 0,
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('purple message count only when unreadMessageCount > 0 (#535)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const MatchesNavIcon(
          icon: Icons.swap_horiz,
          matchCount: 0,
          unreadMessageCount: 5,
        ),
      ),
    );

    expect(find.text('5'), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble), findsNothing);
  });

  testWidgets('both count badges can show together (#535)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const MatchesNavIcon(
          icon: Icons.swap_horiz,
          matchCount: 2,
          unreadMessageCount: 4,
        ),
      ),
    );

    expect(find.text('2'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('counts cap visual label at 99+ (#535)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const MatchesNavIcon(
          icon: Icons.swap_horiz,
          matchCount: 120,
          unreadMessageCount: 150,
        ),
      ),
    );

    expect(find.text('99+'), findsNWidgets(2));
  });
}
