import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/matches_nav_icon.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('no badges when matchCount is 0 and no unread (#535)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const MatchesNavIcon(
          icon: Icons.swap_horiz,
          matchCount: 0,
          hasUnreadMessages: false,
        ),
      ),
    );

    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    expect(find.text('1'), findsNothing);
    expect(find.byIcon(Icons.chat_bubble), findsNothing);
  });

  testWidgets('red match count top-right only when matchCount > 0 (#535)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const MatchesNavIcon(
          icon: Icons.swap_horiz,
          matchCount: 3,
          hasUnreadMessages: false,
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble), findsNothing);

    final text = tester.widget<Text>(find.text('3'));
    expect(text.style?.color, Colors.white);
  });

  testWidgets('purple chat marker only when hasUnreadMessages (#535)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const MatchesNavIcon(
          icon: Icons.swap_horiz,
          matchCount: 0,
          hasUnreadMessages: true,
        ),
      ),
    );

    expect(find.byIcon(Icons.chat_bubble), findsOneWidget);
    expect(find.text('1'), findsNothing);
    expect(find.textContaining(RegExp(r'^\d+$')), findsNothing);
  });

  testWidgets('both badges can show together (#535)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const MatchesNavIcon(
          icon: Icons.swap_horiz,
          matchCount: 2,
          hasUnreadMessages: true,
        ),
      ),
    );

    expect(find.text('2'), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble), findsOneWidget);
  });

  testWidgets('match count caps visual label at 99+ (#535)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const MatchesNavIcon(
          icon: Icons.swap_horiz,
          matchCount: 120,
          hasUnreadMessages: false,
        ),
      ),
    );

    expect(find.text('99+'), findsOneWidget);
  });
}
