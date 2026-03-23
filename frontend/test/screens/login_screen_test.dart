import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/models/models.dart';

void main() {
  testWidgets(
    'LoginScreen shows guest account creation text and start button',
    (WidgetTester tester) async {
      // Provide an initial unauthenticated state
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authProvider.overrideWith((ref) => MockAuthController())],
          child: const MaterialApp(home: LoginScreen()),
        ),
      );

      expect(find.text('ymatch'), findsOneWidget);
      expect(find.text('Trade merch seamlessly.'), findsOneWidget);
      expect(find.text('Start Guest Session'), findsOneWidget);
      expect(find.text('Restore Existing Account'), findsOneWidget);
    },
  );

  testWidgets(
    'LoginScreen tapping Restore reveals TextField and Restore button',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authProvider.overrideWith((ref) => MockAuthController())],
          child: const MaterialApp(home: LoginScreen()),
        ),
      );

      // Tap the restore button
      await tester.tap(find.text('Restore Existing Account'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.text('Restore Account'),
        findsWidgets,
      ); // Can be title and button
      expect(find.text('Cancel'), findsOneWidget);
    },
  );
}

class MockAuthController extends StateNotifier<AsyncValue<User?>>
    implements AuthController {
  MockAuthController() : super(const AsyncValue.data(null));

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
