/// Inventory list tiles (grid / compact / detailed) and merch edit/delete (#494).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_helper.dart';
import 'edit_merch_dialog.dart';
import 'merch_filters.dart';

// --- Grid View Item ---
Widget buildGridInventoryItem(
  BuildContext context,
  WidgetRef ref,
  int eventId,
  User? user,
  Merchandise item,
  Map<int, Map<String, int>> lookup,
  InventoryDisplayMode displayMode,
) {
  final merchInv = lookup[item.id] ?? {};
  final haveQty = merchInv['HAVE'] ?? 0;
  final wantQty = merchInv['WANT'] ?? 0;
  final tradeQty = merchInv['TRADE'] ?? 0;

  final flags = inventoryDisplayFlags(displayMode);
  final showHave = flags.showHave;
  final showWant = flags.showWant;
  final showTrade = flags.showTrade;

  final isOwner =
      user != null && item.hasCreatorId() && item.creatorId == user.id;
  final isDeleted = item.hasIsDeleted() && item.isDeleted;
  final l10n = AppLocalizations.of(context)!;

  return Opacity(
    opacity: isDeleted ? 0.65 : 1.0,
    child: GestureDetector(
      onLongPress: (isOwner && !isDeleted)
          ? () => _showMerchActions(context, ref, eventId, item)
          : null,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: buildImage(
                      item.hasPhotoUrl() ? item.photoUrl : null,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (isDeleted)
                    Positioned(
                      top: 2,
                      left: 2,
                      child: _DeletedBadge(label: l10n.itemDeleted),
                    ),
                  if (isOwner && !isDeleted)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Icon(
                        Icons.edit_note,
                        size: 14,
                        color: Colors.blue[400],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                item.name,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            Row(
              children: [
                if (showHave)
                  Expanded(
                    child: _buildGridCounter(
                      context,
                      l10n.haveShort,
                      haveQty,
                      AppTheme.haveColor,
                      isDeleted
                          ? null
                          : (q) => _updateInv(ref, user, item.id, 'HAVE', q),
                    ),
                  ),
                if (showWant)
                  Expanded(
                    child: _buildGridCounter(
                      context,
                      l10n.wantShort,
                      wantQty,
                      AppTheme.wantColor,
                      isDeleted
                          ? null
                          : (q) => _updateInv(ref, user, item.id, 'WANT', q),
                    ),
                  ),
                if (showTrade)
                  Expanded(
                    child: _buildGridCounter(
                      context,
                      l10n.tradeShort,
                      tradeQty,
                      AppTheme.tradeColor,
                      isDeleted
                          ? null
                          : (q) => _updateInv(ref, user, item.id, 'TRADE', q),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildGridCounter(
  BuildContext context,
  String label,
  int qty,
  Color color,
  void Function(int)? onUpdate,
) {
  final enabled = onUpdate != null;
  return Container(
    decoration: BoxDecoration(
      color: qty > 0 ? color.withValues(alpha: 0.1) : Colors.transparent,
      border: Border(
        top: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 8,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: InkWell(
                onTap: enabled && qty > 0 ? () => onUpdate(qty - 1) : null,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Icon(
                    Icons.remove,
                    size: 12,
                    color: enabled && qty > 0 ? color : Colors.grey,
                  ),
                ),
              ),
            ),
            Text(
              '$qty',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: qty > 0 ? color : Colors.grey,
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: enabled ? () => onUpdate(qty + 1) : null,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Icon(
                    Icons.add,
                    size: 12,
                    color: enabled ? color : Colors.grey,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

// --- Compact List View Item ---
Widget buildCompactInventoryItem(
  BuildContext context,
  WidgetRef ref,
  int eventId,
  User? user,
  Merchandise item,
  Map<int, Map<String, int>> lookup,
  InventoryDisplayMode displayMode,
) {
  final merchInv = lookup[item.id] ?? {};
  final haveQty = merchInv['HAVE'] ?? 0;
  final wantQty = merchInv['WANT'] ?? 0;
  final tradeQty = merchInv['TRADE'] ?? 0;

  final flags = inventoryDisplayFlags(displayMode);
  final showHave = flags.showHave;
  final showWant = flags.showWant;
  final showTrade = flags.showTrade;

  final isOwner =
      user != null && item.hasCreatorId() && item.creatorId == user.id;
  final isDeleted = item.hasIsDeleted() && item.isDeleted;
  final l10n = AppLocalizations.of(context)!;

  return Opacity(
    opacity: isDeleted ? 0.65 : 1.0,
    child: GestureDetector(
      onLongPress: (isOwner && !isDeleted)
          ? () => _showMerchActions(context, ref, eventId, item)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: buildImage(
                item.hasPhotoUrl() ? item.photoUrl : null,
                width: 28,
                height: 28,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isDeleted) ...[
                    const SizedBox(width: 6),
                    _DeletedBadge(label: l10n.itemDeleted),
                  ],
                ],
              ),
            ),
            if (isOwner && !isDeleted)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.edit_note, size: 14, color: Colors.blue[400]),
              ),
            if (showHave)
              _buildCompactCounter(
                context,
                l10n.haveShort,
                haveQty,
                AppTheme.haveColor,
                isDeleted
                    ? null
                    : (q) => _updateInv(ref, user, item.id, 'HAVE', q),
              ),
            if (showHave && (showWant || showTrade)) const SizedBox(width: 4),
            if (showWant)
              _buildCompactCounter(
                context,
                l10n.wantShort,
                wantQty,
                AppTheme.wantColor,
                isDeleted
                    ? null
                    : (q) => _updateInv(ref, user, item.id, 'WANT', q),
              ),
            if (showWant && showTrade) const SizedBox(width: 4),
            if (showTrade)
              _buildCompactCounter(
                context,
                l10n.tradeShort,
                tradeQty,
                AppTheme.tradeColor,
                isDeleted
                    ? null
                    : (q) => _updateInv(ref, user, item.id, 'TRADE', q),
              ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildCompactCounter(
  BuildContext context,
  String label,
  int qty,
  Color color,
  void Function(int)? onUpdate,
) {
  final enabled = onUpdate != null;
  return Container(
    height: 26,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: enabled && qty > 0 ? () => onUpdate(qty - 1) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.remove,
              size: 12,
              color: enabled && qty > 0 ? color : Colors.grey[400],
            ),
          ),
        ),
        Text(
          '$label$qty',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        InkWell(
          onTap: enabled ? () => onUpdate(qty + 1) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.add,
              size: 12,
              color: enabled ? color : Colors.grey[400],
            ),
          ),
        ),
      ],
    ),
  );
}

// --- Detailed List View Item (Original) ---
Widget buildDetailedInventoryItem(
  BuildContext context,
  WidgetRef ref,
  int eventId,
  User? user,
  Merchandise item,
  Map<int, Map<String, int>> lookup,
  InventoryDisplayMode displayMode,
) {
  final merchInv = lookup[item.id] ?? {};
  final haveQty = merchInv['HAVE'] ?? 0;
  final wantQty = merchInv['WANT'] ?? 0;
  final tradeQty = merchInv['TRADE'] ?? 0;

  final flags = inventoryDisplayFlags(displayMode);
  final showHave = flags.showHave;
  final showWant = flags.showWant;
  final showTrade = flags.showTrade;

  final isOwner =
      user != null && item.hasCreatorId() && item.creatorId == user.id;
  final isDeleted = item.hasIsDeleted() && item.isDeleted;
  final l10n = AppLocalizations.of(context)!;

  return Opacity(
    opacity: isDeleted ? 0.65 : 1.0,
    child: GestureDetector(
      onLongPress: (isOwner && !isDeleted)
          ? () => _showMerchActions(context, ref, eventId, item)
          : null,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // #203: removed ReorderableDragStartListener wrapper; the
              // image is no longer a drag handle. Long-press on the
              // card (handled by the outer GestureDetector) is now the
              // only way to trigger the owner's edit/delete menu.
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: buildImage(
                    item.hasPhotoUrl() ? item.photoUrl : null,
                    width: 72,
                    height: 72,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (isDeleted)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: _DeletedBadge(label: l10n.itemDeleted),
                          ),
                        if (isOwner && !isDeleted)
                          Tooltip(
                            message: l10n.youCreatedThisItem,
                            child: Icon(
                              Icons.edit_note,
                              size: 18,
                              color: Colors.blue[400],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (showHave)
                          Expanded(
                            flex: 5,
                            child: _buildStepper(
                              label: 'HAVE',
                              displayLabel: l10n.have,
                              color: AppTheme.haveColor,
                              qty: haveQty,
                              onUpdate: isDeleted
                                  ? null
                                  : (q) => _updateInv(
                                      ref,
                                      user,
                                      item.id,
                                      'HAVE',
                                      q,
                                    ),
                            ),
                          ),
                        if (showHave && (showWant || showTrade))
                          const Spacer(flex: 1),
                        if (showWant)
                          Expanded(
                            flex: 5,
                            child: _buildStepper(
                              label: 'WANT',
                              displayLabel: l10n.want,
                              color: AppTheme.wantColor,
                              qty: wantQty,
                              onUpdate: isDeleted
                                  ? null
                                  : (q) => _updateInv(
                                      ref,
                                      user,
                                      item.id,
                                      'WANT',
                                      q,
                                    ),
                            ),
                          ),
                        if (showWant && showTrade) const Spacer(flex: 1),
                        if (showTrade)
                          Expanded(
                            flex: 5,
                            child: _buildStepper(
                              label: 'TRADE',
                              displayLabel: l10n.trade,
                              color: AppTheme.tradeColor,
                              qty: tradeQty,
                              onUpdate: isDeleted
                                  ? null
                                  : (q) => _updateInv(
                                      ref,
                                      user,
                                      item.id,
                                      'TRADE',
                                      q,
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _updateInv(
  WidgetRef ref,
  User? user,
  int merchId,
  String status,
  int qty,
) async {
  if (user != null) {
    // updateItem rethrows on failure (#239); the optimistic state is
    // rolled back inside the notifier, so the UI reverts on its own.
    // Swallow here so the +/- steppers don't surface an uncaught
    // async error; the rollback is the user-visible signal.
    try {
      await ref
          .read(inventoryProvider(user.id).notifier)
          .updateItem(merchId, status, qty);
    } catch (_) {
      // Optimistic rollback already handled by the notifier.
    }
  }
}

void _showMerchActions(
  BuildContext context,
  WidgetRef ref,
  int eventId,
  Merchandise item,
) {
  final l10n = AppLocalizations.of(context)!;
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: Text(l10n.editItem),
            onTap: () {
              Navigator.pop(ctx);
              _editMerch(context, ref, eventId, item);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(ctx);
              _confirmDeleteMerch(context, ref, eventId, item);
            },
          ),
        ],
      ),
    ),
  );
}

void _editMerch(
  BuildContext context,
  WidgetRef ref,
  int eventId,
  Merchandise item,
) {
  // The dialog holds its own state (picked image + name) and its own ref,
  // so it is a separate ConsumerStatefulWidget rather than an inline
  // AlertDialog. On save it invalidates `merchProvider` so the card list
  // refreshes with the new name/image.
  showDialog<void>(
    context: context,
    builder: (ctx) => EditMerchDialog(eventId: eventId, item: item),
  );
}

void _confirmDeleteMerch(
  BuildContext context,
  WidgetRef ref,
  int eventId,
  Merchandise item,
) {
  final user = ref.read(currentUserProvider);
  final l10n = AppLocalizations.of(context)!;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.deleteItem),
      content: Text(l10n.deleteEventConfirm(item.name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () async {
            if (user != null) {
              try {
                await ref
                    .read(merchControllerProvider.notifier)
                    .deleteMerchByCreator(item.eventId, item.id, user.id);
                ref.invalidate(merchProvider(eventId));
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                // #266: surface delete failure; keep dialog open.
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.errorPrefix(e.toString())),
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  );
                }
              }
            } else if (ctx.mounted) {
              Navigator.pop(ctx);
            }
          },
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
}

Widget _buildStepper({
  required String label,
  required String displayLabel,
  required Color color,
  required int qty,
  void Function(int)? onUpdate,
}) {
  final enabled = onUpdate != null;
  return Container(
    height: 44,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        // Tap areas: left = decrease, right = increase
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled && qty > 0 ? () => onUpdate(qty - 1) : null,
                child: Container(color: Colors.transparent),
              ),
            ),
            Expanded(
              child: GestureDetector(
                key: Key('stepper_inc_$label'),
                behavior: HitTestBehavior.opaque,
                onTap: enabled ? () => onUpdate(qty + 1) : null,
                child: Container(color: Colors.transparent),
              ),
            ),
          ],
        ),
        // −/+ hint icons centered on left/right edges.
        // IgnorePointer so taps on the glyphs reach the half-area
        // GestureDetectors below (#408) — same as the center label.
        Positioned(
          left: 2,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Center(
              child: Text(
                '−',
                style: TextStyle(
                  fontSize: 9,
                  color: enabled && qty > 0
                      ? color.withValues(alpha: 0.5)
                      : Colors.grey.withValues(alpha: 0.3),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 3,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Center(
              child: Text(
                '+',
                style: TextStyle(
                  fontSize: 9,
                  color: enabled
                      ? color.withValues(alpha: 0.5)
                      : Colors.grey.withValues(alpha: 0.3),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        // Centered label + quantity (non-interactive, taps pass through)
        Center(
          child: IgnorePointer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayLabel,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: qty > 0 ? color : Colors.grey[500],
                  ),
                ),
                Text(
                  '$qty',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                    color: qty > 0 ? color : Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// Small badge marking soft-deleted merch.
///
/// ADR 0011: event catalog lists are live-only, so this is primarily defensive
/// for stale client state. Inventory rows still carry `is_deleted` (ADR 0008).
class _DeletedBadge extends StatelessWidget {
  final String label;

  const _DeletedBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.grey[700],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
