/// Self-service event member management dialog (#442).
///
/// Entry point is HomeScreen event-card long-press (#483); the dialog itself
/// is unchanged from the EventDetail flow (list / add / remove editor /
/// transfer creator with confirmation).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/providers.dart';

/// Opens the Manage members dialog for [eventId] using capability flags in
/// [role]. No-op when the caller is not logged in.
Future<void> showManageEventMembersDialog(
  BuildContext context,
  WidgetRef ref, {
  required int eventId,
  required MyEventRoleResponse role,
}) async {
  final user = ref.read(currentUserProvider);
  if (user == null) return;
  final l10n = AppLocalizations.of(context)!;
  final events = ref.read(eventsControllerProvider.notifier);

  Future<List<EventMemberInfo>> loadMembers() =>
      events.listEventMembers(eventId, user.id);

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: Text(l10n.manageMembers),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: FutureBuilder<List<EventMemberInfo>>(
                future: loadMembers(),
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
                      ref.invalidate(myEventRoleProvider(eventId));
                      if (closeOnSuccess && dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      } else {
                        setDialogState(() {});
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(successLabel)));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.errorPrefix(e.toString())),
                            backgroundColor: Theme.of(
                              context,
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
                                      m.username != null &&
                                          m.username!.isNotEmpty
                                      ? '${m.username} (${m.userId})'
                                      : 'ID ${m.userId}';
                                  final roleLabel = m.role == 'creator'
                                      ? l10n.roleCreator
                                      : m.role == 'editor'
                                      ? l10n.roleEditor
                                      : m.role;
                                  return ListTile(
                                    title: Text(label),
                                    subtitle: Text(roleLabel),
                                    trailing:
                                        role.canManageEditors &&
                                            m.role == 'editor'
                                        ? IconButton(
                                            icon: const Icon(
                                              Icons.remove_circle_outline,
                                              color: Colors.red,
                                            ),
                                            tooltip: l10n.removeEditor,
                                            onPressed: () => runAction(
                                              () => events.revokeEventEditor(
                                                eventId,
                                                m.userId,
                                                user.id,
                                              ),
                                              l10n.editorRemoved,
                                            ),
                                          )
                                        : null,
                                  );
                                },
                              ),
                      ),
                      const Divider(),
                      if (role.canManageEditors)
                        ListTile(
                          leading: const Icon(Icons.person_add_alt_1),
                          title: Text(l10n.addEditor),
                          onTap: () async {
                            final selected = await pickUserFromDirectory(
                              dialogContext,
                              ref,
                              title: l10n.pickEditorTitle,
                              excludeUserIds: members
                                  .map((m) => m.userId)
                                  .toSet(),
                            );
                            if (selected == null) return;
                            await runAction(
                              () => events.assignEventEditor(
                                eventId,
                                selected.id,
                                user.id,
                              ),
                              l10n.editorAssigned,
                            );
                          },
                        ),
                      if (role.canTransferCreator)
                        ListTile(
                          leading: const Icon(Icons.swap_horiz),
                          title: Text(l10n.transferCreator),
                          onTap: () async {
                            final selected = await pickUserFromDirectory(
                              dialogContext,
                              ref,
                              title: l10n.pickTransferCreatorTitle,
                              excludeUserIds: {?creatorId},
                            );
                            if (selected == null) return;
                            // Irreversible: confirm before PUT (#442 pr-review).
                            if (!dialogContext.mounted) return;
                            final confirmed = await showDialog<bool>(
                              context: dialogContext,
                              builder: (ctx) => AlertDialog(
                                title: Text(l10n.confirmTransferCreatorTitle),
                                content: Text(
                                  l10n.confirmTransferCreatorBody(
                                    selected.username,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text(l10n.cancel),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(
                                      l10n.confirmTransferCreatorAction,
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                            await runAction(
                              () => events.transferEventCreator(
                                eventId,
                                user.id,
                                selected.id,
                              ),
                              l10n.creatorTransferred,
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
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.cancel),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Shared user picker for self-service member management (#442 / #443).
Future<User?> pickUserFromDirectory(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  Set<int> excludeUserIds = const {},
}) async {
  final l10n = AppLocalizations.of(context)!;
  final users = await ref.read(usersDirectoryProvider.future);
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
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: double.maxFinite,
              height: 360,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: l10n.searchUsersHint,
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => filter = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Text(l10n.noUsersFound))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final u = filtered[index];
                              return ListTile(
                                title: Text(u.username),
                                subtitle: Text('ID: ${u.id}'),
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
                child: Text(l10n.cancel),
              ),
            ],
          );
        },
      );
    },
  );
}
