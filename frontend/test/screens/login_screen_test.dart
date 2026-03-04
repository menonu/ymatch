import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/models/models.dart';

void main() {
  testWidgets('LoginScreen shows guest account creation text and start button', (WidgetTester tester) async {
    // Provide an initial unauthenticated state
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => MockAuthController()),
        ],
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );

    expect(find.text('Welcome to ymatch'), findsOneWidget);
    expect(find.text('Creating your secure guest account...'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('I have a Master Key (Restore)'), findsOneWidget);
  });

  testWidgets('LoginScreen tapping Restore reveals TextField and Restore button', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => MockAuthController()),
        ],
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );

    // Tap the restore button
    await tester.tap(find.text('I have a Master Key (Restore)'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Restore Account'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });
}

class MockAuthController extends StateNotifier<AsyncValue<User?>> implements AuthController {
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
  // TODO: implement client
  get client => throw UnimplementedError();
}
