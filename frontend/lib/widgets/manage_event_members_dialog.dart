/// Shared event/group member management UI (#446 / #494).
///
/// Self-service (Home long-press, #442/#483), admin Events tab (#432), and
/// group-scoped management on EventDetail inject list / assign / revoke /
/// transfer callbacks so all share one dialog without sharing API endpoints.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/providers.dart';

/// API-agnostic member mutations for [showManageEventMembersDialogCore].
///
/// Public, admin, and group paths each build an instance that hits their own
/// controllers.
class EventMemberActions {
  const EventMemberActions({
    required this.loadMembers,
    this.assignEditor,
    this.revokeEditor,
    this.transferCreator,
    required this.loadPickerUsers,
    this.onMutated,
  });

  final Future<List<EventMemberInfo>> Function() loadMembers;

  /// Assign [userId] as editor. Null hides the add-editor action.
  final Future<void> Function(int userId)? assignEditor;

  /// Revoke editor role from [userId]. Null hides remove buttons.
  final Future<void> Function(int userId)? revokeEditor;

  /// Transfer creator to [newCreatorId]. Null hides the transfer action.
  final Future<void> Function(int newCreatorId)? transferCreator;

  /// Users shown in the shared picker (directory vs admin list).
  final Future<List<User>> Function() loadPickerUsers;

  /// Called after a successful mutation (provider invalidation, etc.).
  final VoidCallback? onMutated;
}

/// Optional copy overrides so event- vs group-scoped dialogs share the core UI
/// with different l10n strings (#494).
class MemberDialogCopy {
  const MemberDialogCopy({
    this.pickEditorTitle,
    this.pickTransferCreatorTitle,
    this.confirmTransferTitle,
    this.confirmTransferBody,
    this.creatorTransferred,
  });

  final String? pickEditorTitle;
  final String? pickTransferCreatorTitle;
  final String? confirmTransferTitle;
  final String Function(String username)? confirmTransferBody;
  final String? creatorTransferred;
}

/// Core dialog: list members, assign/revoke editors, optional transfer.
///
/// Capability flags gate the actions independently of which callbacks are set;
/// both must allow an action for it to appear.
///
/// The members [Future] is held in dialog state and only re-created after a
/// successful mutation (#494) — parent rebuilds do not re-fetch.
Future<void> showManageEventMembersDialogCore(
  BuildContext context, {
  required EventMemberActions actions,
  required bool canManageEditors,
  required bool canTransferCreator,
  String? title,
  String? dismissLabel,
  bool showRoleInUserPicker = false,
  MemberDialogCopy copy = const MemberDialogCopy(),
}) async {
  final l10n = AppLocalizations.of(context)!;
  final dialogTitle = title ?? l10n.manageMembers;
  final closeLabel = dismissLabel ?? l10n.cancel;

  final canAssign = canManageEditors && actions.assignEditor != null;
  final canRevoke = canManageEditors && actions.revokeEditor != null;
  final canTransfer = canTransferCreator && actions.transferCreator != null;

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _ManageMembersDialog(
        actions: actions,
        canAssign: canAssign,
        canRevoke: canRevoke,
        canTransfer: canTransfer,
        title: dialogTitle,
        dismissLabel: closeLabel,
        showRoleInUserPicker: showRoleInUserPicker,
        copy: copy,
        scaffoldContext: context,
      );
    },
  );
}

/// Stateful body so [FutureBuilder] keeps a stable [Future] across rebuilds.
class _ManageMembersDialog extends StatefulWidget {
  const _ManageMembersDialog({
    required this.actions,
    required this.canAssign,
    required this.canRevoke,
    required this.canTransfer,
    required this.title,
    required this.dismissLabel,
    required this.showRoleInUserPicker,
    required this.copy,
    required this.scaffoldContext,
  });

  final EventMemberActions actions;
  final bool canAssign;
  final bool canRevoke;
  final bool canTransfer;
  final String title;
  final String dismissLabel;
  final bool showRoleInUserPicker;
  final MemberDialogCopy copy;

  /// Outer context for snackbars (dialog context may unmount on close).
  final BuildContext scaffoldContext;

  @override
  State<_ManageMembersDialog> createState() => _ManageMembersDialogState();
}

class _ManageMembersDialogState extends State<_ManageMembersDialog> {
  late Future<List<EventMemberInfo>> _membersFuture;

  @override
  void initState() {
    super.initState();
    _membersFuture = widget.actions.loadMembers();
  }

  void _reloadMembers() {
    setState(() {
      _membersFuture = widget.actions.loadMembers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final actions = widget.actions;
    final copy = widget.copy;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: FutureBuilder<List<EventMemberInfo>>(
          future: _membersFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Text(l10n.errorPrefix(snap.error.toString()));
            }
            final members = snap.data ?? [];
            final creatorId = members
                .where((m) => m.role == 'creator')
                .map((m) => m.userId)
                .firstOrNull;

            Future<void> runAction(
              Future<void> Function() action,
              String successLabel, {
              bool closeOnSuccess = false,
            }) async {
              try {
                await action();
                actions.onMutated?.call();
                if (!mounted) return;
                if (closeOnSuccess) {
                  Navigator.of(this.context).pop();
                } else {
                  _reloadMembers();
                }
                final messengerContext = widget.scaffoldContext;
                if (messengerContext.mounted) {
                  ScaffoldMessenger.of(
                    messengerContext,
                  ).showSnackBar(SnackBar(content: Text(successLabel)));
                }
              } catch (e) {
                final messengerContext = widget.scaffoldContext;
                if (messengerContext.mounted) {
                  ScaffoldMessenger.of(messengerContext).showSnackBar(
                    SnackBar(
                      content: Text(l10n.errorPrefix(e.toString())),
                      backgroundColor: Theme.of(
                        messengerContext,
                      ).colorScheme.error,
                    ),
                  );
                }
              }
            }

            return Column(
              children: [
                Expanded(
                  child: members.isEmpty
                      ? Center(child: Text(l10n.noMembers))
                      : ListView.builder(
                          itemCount: members.length,
                          itemBuilder: (context, index) {
                            final m = members[index];
                            final label =
                                m.username != null && m.username!.isNotEmpty
                                ? '${m.username} (${m.userId})'
                                : 'ID ${m.userId}';
                            final roleLabel = m.role == 'creator'
                                ? l10n.roleCreator
                                : m.role == 'editor'
                                ? l10n.roleEditor
                                : m.role;
                            return ListTile(
                              key: Key('member_row_${m.userId}'),
                              title: Text(label),
                              subtitle: Text(roleLabel),
                              trailing: widget.canRevoke && m.role == 'editor'
                                  ? IconButton(
                                      key: Key('remove_editor_${m.userId}'),
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                        color: Colors.red,
                                      ),
                                      tooltip: l10n.removeEditor,
                                      onPressed: () => runAction(
                                        () => actions.revokeEditor!(m.userId),
                                        l10n.editorRemoved,
                                      ),
                                    )
                                  : null,
                            );
                          },
                        ),
                ),
                const Divider(),
                if (widget.canAssign)
                  ListTile(
                    key: const Key('add_editor_action'),
                    leading: const Icon(Icons.person_add_alt_1),
                    title: Text(l10n.addEditor),
                    onTap: () async {
                      final selected = await showUserPickerDialog(
                        context,
                        title: copy.pickEditorTitle ?? l10n.pickEditorTitle,
                        loadUsers: actions.loadPickerUsers,
                        excludeUserIds: members.map((m) => m.userId).toSet(),
                        showRoleInSubtitle: widget.showRoleInUserPicker,
                      );
                      if (selected == null) return;
                      await runAction(
                        () => actions.assignEditor!(selected.id),
                        l10n.editorAssigned,
                      );
                    },
                  ),
                if (widget.canTransfer)
                  ListTile(
                    key: const Key('transfer_creator_action'),
                    leading: const Icon(Icons.swap_horiz),
                    title: Text(l10n.transferCreator),
                    onTap: () async {
                      final selected = await showUserPickerDialog(
                        context,
                        title:
                            copy.pickTransferCreatorTitle ??
                            l10n.pickTransferCreatorTitle,
                        loadUsers: actions.loadPickerUsers,
                        excludeUserIds: {?creatorId},
                        showRoleInSubtitle: widget.showRoleInUserPicker,
                      );
                      if (selected == null) return;
                      // Irreversible: confirm before PUT (#442 pr-review).
                      if (!context.mounted) return;
                      final confirmTitle =
                          copy.confirmTransferTitle ??
                          l10n.confirmTransferCreatorTitle;
                      final confirmBody =
                          copy.confirmTransferBody?.call(selected.username) ??
                          l10n.confirmTransferCreatorBody(selected.username);
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(confirmTitle),
                          content: Text(confirmBody),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(l10n.cancel),
                            ),
                            ElevatedButton(
                              key: const Key('confirm_transfer_creator'),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(l10n.confirmTransferCreatorAction),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      await runAction(
                        () => actions.transferCreator!(selected.id),
                        copy.creatorTransferred ?? l10n.creatorTransferred,
                        closeOnSuccess: true,
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.dismissLabel),
        ),
      ],
    );
  }
}

/// Self-service entry: Home long-press manage-members (#442 / #483).
///
/// Hits public `/events/...` endpoints via [EventsController].
Future<void> showManageEventMembersDialog(
  BuildContext context,
  WidgetRef ref, {
  required int eventId,
  required MyEventRoleResponse role,
}) async {
  final user = ref.read(currentUserProvider);
  if (user == null) return;
  final events = ref.read(eventsControllerProvider.notifier);

  await showManageEventMembersDialogCore(
    context,
    canManageEditors: role.canManageEditors,
    canTransferCreator: role.canTransferCreator,
    actions: EventMemberActions(
      loadMembers: () => events.listEventMembers(eventId, user.id),
      assignEditor: (targetId) =>
          events.assignEventEditor(eventId, targetId, user.id),
      revokeEditor: (targetId) =>
          events.revokeEventEditor(eventId, targetId, user.id),
      transferCreator: (newCreatorId) =>
          events.transferEventCreator(eventId, user.id, newCreatorId),
      loadPickerUsers: () => ref.read(usersDirectoryProvider.future),
      onMutated: () => ref.invalidate(myEventRoleProvider(eventId)),
    ),
  );
}

/// Group-scoped member management on EventDetail (#443 / #494).
///
/// Reuses the same dialog core as event members; hits group endpoints via
/// [EventsController].
Future<void> showManageGroupMembersDialog(
  BuildContext context,
  WidgetRef ref, {
  required int eventId,
  required String groupName,
  required MyGroupRoleResponse role,
}) async {
  final user = ref.read(currentUserProvider);
  if (user == null) return;
  final l10n = AppLocalizations.of(context)!;
  final events = ref.read(eventsControllerProvider.notifier);

  await showManageEventMembersDialogCore(
    context,
    title: l10n.manageGroupMembers,
    canManageEditors: role.canManageEditors,
    canTransferCreator: role.canTransferCreator,
    copy: MemberDialogCopy(
      pickEditorTitle: l10n.pickGroupEditorTitle,
      pickTransferCreatorTitle: l10n.pickTransferGroupCreatorTitle,
      confirmTransferTitle: l10n.confirmTransferGroupCreatorTitle,
      confirmTransferBody: l10n.confirmTransferGroupCreatorBody,
      creatorTransferred: l10n.groupCreatorTransferred,
    ),
    actions: EventMemberActions(
      loadMembers: () => events.listGroupMembers(eventId, groupName, user.id),
      assignEditor: role.canManageEditors
          ? (targetId) =>
                events.assignGroupEditor(eventId, groupName, targetId, user.id)
          : null,
      revokeEditor: role.canManageEditors
          ? (targetId) =>
                events.revokeGroupEditor(eventId, groupName, targetId, user.id)
          : null,
      transferCreator: role.canTransferCreator
          ? (newCreatorId) => events.transferGroupCreator(
              eventId,
              groupName,
              user.id,
              newCreatorId,
            )
          : null,
      loadPickerUsers: () => ref.read(usersDirectoryProvider.future),
      onMutated: () {
        ref.invalidate(
          myGroupRoleProvider((eventId: eventId, groupName: groupName)),
        );
        ref.invalidate(eventGroupsProvider(eventId));
      },
    ),
  );
}

/// Admin Events-tab "Manage editors" entry (#432 / #446).
///
/// Hits `/admin/events/...` endpoints via [AdminController]. Creator transfer
/// remains a separate popup-menu action on the Events tab.
///
/// No [EventMemberActions.onMutated]: the Events tab list does not show editor
/// membership, so invalidating [eventsProvider] would only force a full-tab
/// reload under the open dialog. Member list refresh is via setState on the
/// held Future (#494).
Future<void> showAdminManageEventMembersDialog(
  BuildContext context,
  WidgetRef ref, {
  required int eventId,
  required String eventName,
  required int adminUserId,
}) async {
  final admin = ref.read(adminControllerProvider.notifier);

  await showManageEventMembersDialogCore(
    context,
    // Preserve #432 admin wording so existing dashboard tests keep matching.
    title: 'Editors — $eventName',
    dismissLabel: 'Close',
    showRoleInUserPicker: true,
    canManageEditors: true,
    canTransferCreator: false,
    actions: EventMemberActions(
      loadMembers: () => admin.listEventMembers(eventId, adminUserId),
      assignEditor: (targetId) =>
          admin.assignEventEditor(eventId, targetId, adminUserId),
      revokeEditor: (targetId) =>
          admin.revokeEventEditor(eventId, targetId, adminUserId),
      loadPickerUsers: () => ref.read(adminUsersProvider.future),
    ),
  );
}

/// Shared searchable user picker (#442 / #446).
///
/// Callers supply [loadUsers] so public directory and admin user lists stay
/// separate. Banned users are always filtered out.
Future<User?> showUserPickerDialog(
  BuildContext context, {
  required String title,
  required Future<List<User>> Function() loadUsers,
  Set<int> excludeUserIds = const {},
  bool showRoleInSubtitle = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final users = await loadUsers();
  final candidates =
      users
          .where((u) => !excludeUserIds.contains(u.id))
          .where((u) => !(u.hasIsBanned() && u.isBanned))
          .toList()
        ..sort((a, b) => a.username.compareTo(b.username));

  if (!context.mounted) return null;
  return showDialog<User>(
    context: context,
    builder: (context) {
      var filter = '';
      return StatefulBuilder(
        builder: (context, setState) {
          final filtered = filter.isEmpty
              ? candidates
              : candidates
                    .where(
                      (u) =>
                          u.username.toLowerCase().contains(
                            filter.toLowerCase(),
                          ) ||
                          '${u.id}'.contains(filter),
                    )
                    .toList();
          final searchHint =
              l10n?.searchUsersHint ?? 'Search by username or id';
          final emptyLabel = l10n?.noUsersFound ?? 'No users found';
          final cancelLabel = l10n?.cancel ?? 'Cancel';
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: double.maxFinite,
              height: 360,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: searchHint,
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => filter = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Text(emptyLabel))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final u = filtered[index];
                              final role = u.hasRole() ? u.role : 'user';
                              return ListTile(
                                key: Key('user_pick_${u.id}'),
                                title: Text(u.username),
                                subtitle: Text(
                                  showRoleInSubtitle
                                      ? 'ID: ${u.id} | $role'
                                      : 'ID: ${u.id}',
                                ),
                                onTap: () => Navigator.pop(context, u),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(cancelLabel),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Convenience wrapper: load public user directory then open the picker.
///
/// Used by callers that only need the directory picker outside the members
/// dialog core.
Future<User?> pickUserFromDirectory(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  Set<int> excludeUserIds = const {},
}) {
  return showUserPickerDialog(
    context,
    title: title,
    loadUsers: () => ref.read(usersDirectoryProvider.future),
    excludeUserIds: excludeUserIds,
  );
}
