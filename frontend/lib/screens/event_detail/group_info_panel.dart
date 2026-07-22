/// Active-tab group description panel (#128 / #494).
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../utils/group_display.dart';
import '../../utils/image_helper.dart';

/// Panel showing the active tab's group name + description (#128).
///
/// Tracks the current tab via [DefaultTabController] so switching tabs
/// updates the panel without closing it.
class GroupInfoPanel extends StatelessWidget {
  const GroupInfoPanel({
    super.key,
    required this.groupKeys,
    required this.groupByName,
    required this.user,
    required this.otherItems,
    required this.onClose,
    required this.onEditGroup,
  });

  final List<String> groupKeys;
  final Map<String, MerchandiseGroup> groupByName;
  final User? user;
  final String otherItems;
  final VoidCallback onClose;
  final void Function(String groupName, MerchandiseGroup? meta) onEditGroup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Builder(
      builder: (context) {
        final tabCtrl = DefaultTabController.of(context);
        return AnimatedBuilder(
          animation: tabCtrl,
          builder: (context, _) {
            final index = tabCtrl.index.clamp(0, groupKeys.length - 1);
            final groupName = groupKeys[index];
            final meta = groupByName[groupName];
            final description =
                meta != null &&
                    meta.hasDescription() &&
                    meta.description.trim().isNotEmpty
                ? meta.description.trim()
                : null;
            // Local for promotion: [user] is a field and is not promoted.
            final currentUser = user;
            final isGroupCreator =
                currentUser != null &&
                meta != null &&
                meta.hasCreatedBy() &&
                meta.createdBy == currentUser.id;
            // Synthetic "Other items" bucket has no formal group row.
            final isSynthetic = groupName == otherItems;

            return Material(
              elevation: 1,
              color: Colors.blueGrey.shade50,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.info_outline, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            groupDisplayName(groupName, groupByName),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isSynthetic
                                ? l10n.noGroupDescription
                                : (description ?? l10n.noGroupDescription),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: description == null
                                      ? Colors.grey[600]
                                      : null,
                                  fontStyle: description == null
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                          ),
                          // Description image below text, width-fit (#404).
                          if (!isSynthetic &&
                              meta != null &&
                              meta.hasPhotoUrl() &&
                              meta.photoUrl.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: double.infinity,
                                child: buildImage(
                                  meta.photoUrl,
                                  width: double.infinity,
                                  fit: BoxFit.fitWidth,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isGroupCreator && !isSynthetic)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: l10n.editGroup,
                        onPressed: () => onEditGroup(groupName, meta),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: l10n.cancel,
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
