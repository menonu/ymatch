import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen renders correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );

    // Verify that our login screen texts are rendered.
    expect(find.text('Welcome to ymatch'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('I have a Master Key (Restore)'), findsOneWidget);
  });
}
