import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps [child] with the localization delegates so screens that call
/// `AppLocalizations.of(context)` resolve strings in widget tests.
Widget _localized(Widget child, {Locale? locale}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

/// A [AuthController] stand-in so [HomeScreen] does not trigger
/// network calls through `apiClientProvider`.
class _MockAuthController extends StateNotifier<AsyncValue<User?>>
    implements AuthController {
  _MockAuthController([User? user]) : super(AsyncValue.data(user));

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
  get client => throw UnimplementedError();
}

ApiClient _failingCreateApi() {
  final config = ConfigService()..setBaseUrlForTest('http://localhost:3000');
  return ApiClient(
    config,
    client: MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/api/v1/events') {
        return http.Response('Conflict', 409);
      }
      return http.Response('[]', 200);
    }),
  );
}

/// Fails PUT rename and DELETE-by-creator paths used by the owner long-press
/// menus (#395 / #266).
ApiClient _failingEventMutationsApi() {
  final config = ConfigService()..setBaseUrlForTest('http://localhost:3000');
  return ApiClient(
    config,
    client: MockClient((request) async {
      if (request.method == 'PUT' &&
          request.url.path.startsWith('/api/v1/events/')) {
        return http.Response('Conflict', 409);
      }
      if (request.method == 'DELETE' &&
          request.url.path.startsWith('/api/v1/admin/events/')) {
        return http.Response('Forbidden', 403);
      }
      return http.Response('[]', 200);
    }),
  );
}

Event _ownedEvent() => Event()
  ..id = 42
  ..name = 'Owned Fest'
  ..creatorId = 1;

Event _otherEvent() => Event()
  ..id = 7
  ..name = 'Other Fest'
  ..creatorId = 99;

void main() {
  // The AppBar help icon watches howToHintSeenProvider, which reads
  // SharedPreferences — provide the in-memory mock so widget tests don't hit
  // the platform channel.
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'filter tabs fit within screen width at a narrow viewport (#415)',
    (WidgetTester tester) async {
      // Representative narrow phone width. With `devicePixelRatio = 1.0` the
      // physical size equals the logical size in logical pixels.
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController()),
            eventsProvider.overrideWith((ref) async => <Event>[]),
          ],
          // Japanese labels are the longest of the supported locales
          // (e.g. "すべてのイベント"), so they are the worst case for fit.
          child: _localized(const HomeScreen(), locale: const Locale('ja')),
        ),
      );
      await tester.pumpAndSettle();

      final buttonFinder = find.byType(SegmentedButton<EventFilter>);
      expect(buttonFinder, findsOneWidget);

      // The filter bar lives in a Container with 16px horizontal padding, so
      // with `expandedInsets: EdgeInsets.zero` the bar must fill exactly
      // screenWidth - 32 — no horizontal scroll, no overflow, one row.
      const availableWidth = 360 - 32;
      final buttonWidth = tester.getSize(buttonFinder).width;
      expect(
        buttonWidth,
        closeTo(availableWidth, 0.5),
        reason:
            'filter tab bar ($buttonWidth) does not fill the available '
            'width ($availableWidth)',
      );

      // The three segments must share the available width equally so the bar
      // fills the row instead of left-aligning at intrinsic width. Each
      // segment renders as its own TextButton, so measure those.
      final segments = find.descendant(
        of: buttonFinder,
        matching: find.byType(TextButton),
      );
      expect(segments, findsNWidgets(3));
      final widths = tester
          .renderObjectList(segments)
          .map((r) => (r as RenderBox).size.width)
          .toList();
      expect(
        widths.every((w) => (w - widths.first).abs() < 0.5),
        isTrue,
        reason: 'segment widths are not equal: $widths',
      );

      // No label may wrap to a second line — the bar must stay a single row.
      // A wrapped label's paragraph height is roughly double a single line, so
      // compare every label's height against the shortest one (which always
      // fits on one line) and reject any that grew.
      final labelHeights = <String, double>{};
      for (final label in const ['すべてのイベント', 'お気に入り', 'マイアイテム']) {
        final paragraph =
            tester.renderObject(find.text(label)) as RenderParagraph;
        labelHeights[label] = paragraph.size.height;
      }
      final minHeight = labelHeights.values.reduce(math.min);
      for (final entry in labelHeights.entries) {
        expect(
          entry.value,
          lessThan(minHeight * 1.5),
          reason:
              '"${entry.key}" wrapped to more than one line '
              '(height ${entry.value} vs single-line $minHeight)',
        );
      }

      // The issue also requires labels to stay *fully visible* (single line).
      // `maxLines: 1` + `TextOverflow.ellipsis` would silently truncate a
      // too-wide label without wrapping — the height check above cannot see
      // that. Measure each label's intrinsic text width and confirm it fits
      // inside its segment's content box (segment width minus the 6px gutters
      // applied via `SegmentedButton.styleFrom(padding: ...)`).
      const segmentHorizontalPadding = 6.0;
      final segmentContentWidth =
          (buttonWidth / 3) - segmentHorizontalPadding * 2;
      for (final label in const ['すべてのイベント', 'お気に入り', 'マイアイテム']) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: const TextStyle(fontSize: 12)),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: double.infinity);
        expect(
          painter.width,
          lessThanOrEqualTo(segmentContentWidth),
          reason:
              '"$label" intrinsic width ${painter.width.toStringAsFixed(1)} '
              'exceeds segment content width '
              '${segmentContentWidth.toStringAsFixed(1)} — the label would '
              'truncate with ellipsis instead of staying fully visible',
        );
        painter.dispose();
      }
    },
  );

  testWidgets(
    'filter tab button keeps a fixed width regardless of selection (#324)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController()),
            eventsProvider.overrideWith((ref) async => <Event>[]),
          ],
          child: _localized(const HomeScreen(), locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();

      final buttonFinder = find.byType(SegmentedButton<EventFilter>);
      expect(buttonFinder, findsOneWidget);
      final widthBefore = tester.getSize(buttonFinder).width;

      // Cycle through every tab. The width must stay constant regardless of
      // which segment is selected (no check icon may be added/removed).
      for (final label in const ['Favorites', 'All Events', 'My Items']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();

        // The selected tab must not grow (e.g. by adding a check icon) and
        // the unselected tab must not shrink — width is state-independent.
        expect(
          tester.getSize(buttonFinder).width,
          equals(widthBefore),
          reason: 'width changed after selecting "$label"',
        );
      }
    },
  );

  testWidgets(
    'HomeScreen AppBar info icon opens the how-to guide sheet (#336)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController()),
            eventsProvider.overrideWith((ref) async => <Event>[]),
          ],
          child: _localized(const HomeScreen(), locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();

      // The AppBar exposes a help/info icon that opens the guide inline.
      expect(find.byTooltip('How to Trade'), findsOneWidget);
      await tester.tap(find.byTooltip('How to Trade'));
      await tester.pumpAndSettle();

      expect(find.text('How to Trade'), findsOneWidget);
      expect(
        find.text('Go to the Items tab and find your event.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'HomeScreen help icon is emphasized on first login and plain after '
    'opened (#336)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController()),
            eventsProvider.overrideWith((ref) async => <Event>[]),
          ],
          child: _localized(const HomeScreen(), locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();

      // First login ("not seen"): the help icon is emphasized with a badge.
      expect(find.byType(Badge), findsOneWidget);
      expect(find.byTooltip('How to Trade'), findsOneWidget);

      await tester.tap(find.byTooltip('How to Trade'));
      await tester.pumpAndSettle();

      // Opening the guide marks it seen → the emphasis (badge) is removed.
      expect(find.byType(Badge), findsNothing);
      expect(find.text('How to Trade'), findsOneWidget);
    },
  );

  testWidgets(
    'create event failure shows error SnackBar and keeps dialog open (#266)',
    (WidgetTester tester) async {
      final user = User()
        ..id = 1
        ..username = 'creator';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(user)),
            eventsProvider.overrideWith((ref) async => <Event>[]),
            apiClientProvider.overrideWithValue(_failingCreateApi()),
          ],
          child: _localized(const HomeScreen(), locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();

      // Open the create-event dialog via FAB.
      await tester.tap(find.text('New Event'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // Scope to the dialog TextField (SearchBar also exposes a TextField).
      final dialogField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogField, 'My Fest');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(ElevatedButton, 'Create'),
        ),
      );
      await tester.pumpAndSettle();

      // Failure must be visible; dialog must stay open (not silent success).
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Error:'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets(
    'rename event failure shows error SnackBar and keeps dialog open (#395)',
    (WidgetTester tester) async {
      final user = User()
        ..id = 1
        ..username = 'creator';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(user)),
            eventsProvider.overrideWith((ref) async => [_ownedEvent()]),
            apiClientProvider.overrideWithValue(_failingEventMutationsApi()),
          ],
          child: _localized(const HomeScreen(), locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Owned Fest'), findsOneWidget);
      await tester.longPress(find.text('Owned Fest'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit Name'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      final dialogField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogField, 'Renamed Fest');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(ElevatedButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Error:'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets(
    'delete event failure shows error SnackBar and keeps dialog open (#395)',
    (WidgetTester tester) async {
      final user = User()
        ..id = 1
        ..username = 'creator';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(user)),
            eventsProvider.overrideWith((ref) async => [_ownedEvent()]),
            apiClientProvider.overrideWithValue(_failingEventMutationsApi()),
          ],
          child: _localized(const HomeScreen(), locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Owned Fest'));
      await tester.pumpAndSettle();

      // Bottom sheet "Delete" opens the confirm dialog.
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(ElevatedButton, 'Delete'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Error:'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  // --- Event member management via home long-press (#483) ---

  testWidgets(
    'owner long-press sheet includes Manage members when role allows (#483)',
    (tester) async {
      final user = User()
        ..id = 1
        ..username = 'creator';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(user)),
            eventsProvider.overrideWith((ref) async => [_ownedEvent()]),
            myEventRoleProvider(42).overrideWith(
              (ref) async => MyEventRoleResponse()
                ..canManageEditors = true
                ..canTransferCreator = true,
            ),
            apiClientProvider.overrideWithValue(
              ApiClient(
                ConfigService()..setBaseUrlForTest('http://localhost:3000'),
                client: MockClient((_) async => http.Response('[]', 200)),
              ),
            ),
          ],
          child: _localized(const HomeScreen(), locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Owned Fest'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Name'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.byKey(const Key('manage_members_action')), findsOneWidget);
      expect(find.text('Manage members'), findsOneWidget);
    },
  );

  testWidgets(
    'editor (non-owner) long-press shows Manage members only (#483)',
    (tester) async {
      final user = User()
        ..id = 1
        ..username = 'editor';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(user)),
            eventsProvider.overrideWith((ref) async => [_otherEvent()]),
            myEventRoleProvider(7).overrideWith(
              (ref) async => MyEventRoleResponse()
                ..canManageEditors = true
                ..canTransferCreator = false,
            ),
            apiClientProvider.overrideWithValue(
              ApiClient(
                ConfigService()..setBaseUrlForTest('http://localhost:3000'),
                client: MockClient((_) async => http.Response('[]', 200)),
              ),
            ),
          ],
          child: _localized(const HomeScreen(), locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Other Fest'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('manage_members_action')), findsOneWidget);
      expect(find.text('Manage members'), findsOneWidget);
      expect(find.text('Edit Name'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    },
  );

  testWidgets('plain viewer has no long-press manage entry (#483)', (
    tester,
  ) async {
    final user = User()
      ..id = 1
      ..username = 'viewer';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _MockAuthController(user)),
          eventsProvider.overrideWith((ref) async => [_otherEvent()]),
          myEventRoleProvider(7).overrideWith(
            (ref) async => MyEventRoleResponse()
              ..canManageEditors = false
              ..canTransferCreator = false,
          ),
          apiClientProvider.overrideWithValue(
            ApiClient(
              ConfigService()..setBaseUrlForTest('http://localhost:3000'),
              client: MockClient((_) async => http.Response('[]', 200)),
            ),
          ),
        ],
        child: _localized(const HomeScreen(), locale: const Locale('en')),
      ),
    );
    await tester.pumpAndSettle();

    // Long-press is attached for signed-in users but resolves role lazily and
    // no-ops for viewers (no sheet / manage tile that would 403) (#483).
    await tester.longPress(find.text('Other Fest'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('manage_members_action')), findsNothing);
    expect(find.text('Manage members'), findsNothing);
    expect(find.text('Edit Name'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets(
    'Transfer creator requires confirmation before PUT from home (#442/#483)',
    (tester) async {
      var putCount = 0;
      final user = User()
        ..id = 1
        ..username = 'creator';
      final client = ApiClient(
        ConfigService()..setBaseUrlForTest('http://localhost:3000'),
        client: MockClient((request) async {
          final path = request.url.path;
          if (request.method == 'GET' && path == '/api/v1/events/42/members') {
            return http.Response(
              jsonEncode({
                'members': [
                  {'userId': 1, 'role': 'creator', 'username': 'me'},
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'GET' && path == '/api/v1/users') {
            return http.Response(
              jsonEncode([
                {'id': 1, 'username': 'me'},
                {'id': 9, 'username': 'alice'},
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'PUT' && path == '/api/v1/events/42/creator') {
            putCount++;
            return http.Response('{}', 200);
          }
          return http.Response('[]', 200);
        }),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthController(user)),
            eventsProvider.overrideWith((ref) async => [_ownedEvent()]),
            myEventRoleProvider(42).overrideWith(
              (ref) async => MyEventRoleResponse()
                ..canManageEditors = true
                ..canTransferCreator = true,
            ),
            apiClientProvider.overrideWithValue(client),
          ],
          child: _localized(const HomeScreen(), locale: const Locale('en')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Owned Fest'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('manage_members_action')));
      await tester.pumpAndSettle();

      expect(find.text('Manage members'), findsOneWidget);
      await tester.tap(find.text('Transfer creator'));
      await tester.pumpAndSettle();

      expect(find.text('Transfer event creator'), findsOneWidget);
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      expect(find.text('Transfer event creator?'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(putCount, 0);

      await tester.tap(find.text('Transfer creator'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();
      expect(putCount, 1);
    },
  );
}
