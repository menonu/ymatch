// Widget tests for shared event member management UI (#446).
//
// Exercises the API-agnostic core dialog with injectable callbacks so list /
// assign / revoke / transfer flows are covered without hitting real network.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/providers/providers.dart';
import 'package:frontend/widgets/manage_event_members_dialog.dart';

Widget _localized(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

User _user({required int id, required String username, String role = 'user'}) =>
    User()
      ..id = id
      ..username = username
      ..role = role;

List<EventMemberInfo> _defaultMembers() => const [
  EventMemberInfo(userId: 1, role: 'creator', username: 'owner'),
  EventMemberInfo(userId: 2, role: 'editor', username: 'ed'),
];

List<User> _directory() => [
  _user(id: 1, username: 'owner'),
  _user(id: 2, username: 'ed'),
  _user(id: 3, username: 'alice'),
  _user(id: 4, username: 'bob'),
];

/// Host that opens the core dialog on first frame with controllable fakes.
class _DialogHost extends StatefulWidget {
  const _DialogHost({
    required this.actions,
    required this.canManageEditors,
    required this.canTransferCreator,
    this.title,
    this.dismissLabel,
    this.showRoleInUserPicker = false,
  });

  final EventMemberActions actions;
  final bool canManageEditors;
  final bool canTransferCreator;
  final String? title;
  final String? dismissLabel;
  final bool showRoleInUserPicker;

  @override
  State<_DialogHost> createState() => _DialogHostState();
}

class _DialogHostState extends State<_DialogHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showManageEventMembersDialogCore(
        context,
        actions: widget.actions,
        canManageEditors: widget.canManageEditors,
        canTransferCreator: widget.canTransferCreator,
        title: widget.title,
        dismissLabel: widget.dismissLabel,
        showRoleInUserPicker: widget.showRoleInUserPicker,
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  testWidgets('lists members with role labels (#446)', (tester) async {
    var loadCount = 0;
    await tester.pumpWidget(
      _localized(
        _DialogHost(
          canManageEditors: true,
          canTransferCreator: true,
          actions: EventMemberActions(
            loadMembers: () async {
              loadCount++;
              return _defaultMembers();
            },
            loadPickerUsers: () async => _directory(),
            assignEditor: (_) async {},
            revokeEditor: (_) async {},
            transferCreator: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Manage members'), findsOneWidget);
    expect(find.text('owner (1)'), findsOneWidget);
    expect(find.text('ed (2)'), findsOneWidget);
    expect(find.text('creator'), findsOneWidget);
    expect(find.text('editor'), findsOneWidget);
    expect(find.byKey(const Key('member_row_1')), findsOneWidget);
    expect(find.byKey(const Key('member_row_2')), findsOneWidget);
    // Creator has no remove control; editor does.
    expect(find.byKey(const Key('remove_editor_1')), findsNothing);
    expect(find.byKey(const Key('remove_editor_2')), findsOneWidget);
    expect(loadCount, greaterThanOrEqualTo(1));
  });

  testWidgets('assign editor calls callback, refreshes list, snackbar (#446)', (
    tester,
  ) async {
    final members = List<EventMemberInfo>.from(_defaultMembers());
    final assigned = <int>[];
    var mutated = 0;

    await tester.pumpWidget(
      _localized(
        _DialogHost(
          canManageEditors: true,
          canTransferCreator: false,
          actions: EventMemberActions(
            loadMembers: () async => List.of(members),
            loadPickerUsers: () async => _directory(),
            assignEditor: (id) async {
              assigned.add(id);
              members.add(
                EventMemberInfo(userId: id, role: 'editor', username: 'alice'),
              );
            },
            revokeEditor: (_) async {},
            onMutated: () => mutated++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add_editor_action')));
    await tester.pumpAndSettle();

    expect(find.text('Add event editor'), findsOneWidget);
    // Existing members excluded from picker.
    expect(find.byKey(const Key('user_pick_1')), findsNothing);
    expect(find.byKey(const Key('user_pick_2')), findsNothing);
    expect(find.byKey(const Key('user_pick_3')), findsOneWidget);

    await tester.tap(find.text('alice'));
    await tester.pumpAndSettle();

    expect(assigned, [3]);
    expect(mutated, 1);
    expect(find.text('alice (3)'), findsOneWidget);
    expect(find.text('Editor assigned'), findsOneWidget);
  });

  testWidgets('revoke editor calls callback and refreshes (#446)', (
    tester,
  ) async {
    final members = List<EventMemberInfo>.from(_defaultMembers());
    final revoked = <int>[];
    var mutated = 0;

    await tester.pumpWidget(
      _localized(
        _DialogHost(
          canManageEditors: true,
          canTransferCreator: false,
          actions: EventMemberActions(
            loadMembers: () async => List.of(members),
            loadPickerUsers: () async => _directory(),
            assignEditor: (_) async {},
            revokeEditor: (id) async {
              revoked.add(id);
              members.removeWhere((m) => m.userId == id);
            },
            onMutated: () => mutated++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ed (2)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('remove_editor_2')));
    await tester.pumpAndSettle();

    expect(revoked, [2]);
    expect(mutated, 1);
    expect(find.text('ed (2)'), findsNothing);
    expect(find.text('Editor removed'), findsOneWidget);
  });

  testWidgets(
    'transfer creator requires confirm; cancel skips callback (#446)',
    (tester) async {
      final transferred = <int>[];

      await tester.pumpWidget(
        _localized(
          _DialogHost(
            canManageEditors: true,
            canTransferCreator: true,
            actions: EventMemberActions(
              loadMembers: () async => _defaultMembers(),
              loadPickerUsers: () async => _directory(),
              assignEditor: (_) async {},
              revokeEditor: (_) async {},
              transferCreator: (id) async => transferred.add(id),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('transfer_creator_action')));
      await tester.pumpAndSettle();
      expect(find.text('Transfer event creator'), findsOneWidget);

      // Current creator excluded.
      expect(find.byKey(const Key('user_pick_1')), findsNothing);
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      expect(find.text('Transfer event creator?'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(transferred, isEmpty);

      // Confirm path.
      await tester.tap(find.byKey(const Key('transfer_creator_action')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_transfer_creator')));
      await tester.pumpAndSettle();

      expect(transferred, [3]);
      expect(find.text('Event creator updated'), findsOneWidget);
      // Dialog closes after successful transfer.
      expect(find.text('Manage members'), findsNothing);
    },
  );

  testWidgets('capability flags hide assign/transfer when false (#446)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _localized(
        _DialogHost(
          canManageEditors: false,
          canTransferCreator: false,
          actions: EventMemberActions(
            loadMembers: () async => _defaultMembers(),
            loadPickerUsers: () async => _directory(),
            assignEditor: (_) async {},
            revokeEditor: (_) async {},
            transferCreator: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add_editor_action')), findsNothing);
    expect(find.byKey(const Key('transfer_creator_action')), findsNothing);
    expect(find.byKey(const Key('remove_editor_2')), findsNothing);
  });

  testWidgets('error during assign surfaces snackbar (#446)', (tester) async {
    await tester.pumpWidget(
      _localized(
        _DialogHost(
          canManageEditors: true,
          canTransferCreator: false,
          actions: EventMemberActions(
            loadMembers: () async => _defaultMembers(),
            loadPickerUsers: () async => _directory(),
            assignEditor: (_) async {
              throw Exception('denied');
            },
            revokeEditor: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add_editor_action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alice'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Error:'), findsOneWidget);
    // Dialog stays open.
    expect(find.text('Manage members'), findsOneWidget);
  });

  testWidgets('custom title and dismiss label for admin-style heading (#446)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _localized(
        _DialogHost(
          title: 'Editors — Live Event',
          dismissLabel: 'Close',
          showRoleInUserPicker: true,
          canManageEditors: true,
          canTransferCreator: false,
          actions: EventMemberActions(
            loadMembers: () async => const [
              EventMemberInfo(userId: 1, role: 'creator', username: 'alice'),
            ],
            loadPickerUsers: () async => [
              _user(id: 1, username: 'alice'),
              _user(id: 2, username: 'carol'),
            ],
            assignEditor: (_) async {},
            revokeEditor: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Editors — Live Event'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('alice (1)'), findsOneWidget);
    expect(find.text('creator'), findsOneWidget);
  });
}
