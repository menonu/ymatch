library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../utils/image_helper.dart';

/// Group description edit dialog (#128 / #404). Owns its controller so dispose
/// cannot race the route close animation. Image attach/replace uses the same
/// pick + upload flow as merch edit.
class EditGroupDialog extends ConsumerStatefulWidget {
  final int eventId;
  final int userId;
  final String groupName;
  // #425: editable cosmetic label. Pre-filled with the current display_name,
  // falling back to the (immutable) group_name key so the field never opens
  // empty. Saving writes `display_name`; the key is never sent.
  final String initialDisplayName;
  final String initialDescription;
  final String? initialPhotoUrl;

  const EditGroupDialog({
    super.key,
    required this.eventId,
    required this.userId,
    required this.groupName,
    required this.initialDisplayName,
    required this.initialDescription,
    this.initialPhotoUrl,
  });

  @override
  ConsumerState<EditGroupDialog> createState() => EditGroupDialogState();
}

class EditGroupDialogState extends ConsumerState<EditGroupDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  bool _saving = false;

  /// Preview URL (existing remote or base64 of a newly picked image).
  String? _previewUrl;

  /// Raw bytes of a newly picked image (null if no change / no new pick).
  List<int>? _pickedImageBytes;
  String? _pickedImageName;

  /// True when the user explicitly cleared the image.
  bool _removePhoto = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialDisplayName);
    _descCtrl = TextEditingController(text: widget.initialDescription);
    _previewUrl = widget.initialPhotoUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await pickMerchImage(context);
    if (picked == null || !mounted) return;
    setState(() {
      _pickedImageBytes = picked.bytes;
      _pickedImageName = picked.name;
      _previewUrl = picked.previewUrl;
      _removePhoto = false;
    });
  }

  void _clearImage() {
    setState(() {
      _pickedImageBytes = null;
      _pickedImageName = null;
      _previewUrl = null;
      _removePhoto = true;
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    // An empty display name clears it (the backend stores NULL), so the label
    // reverts to the immutable group_name key — that is the UI's "reset to
    // key" path (#425 AC #8). The field opens pre-filled with the current
    // display name (or the key), so clearing is a deliberate action.
    final displayName = _nameCtrl.text.trim();

    setState(() => _saving = true);
    try {
      String? photoUrl;
      var updatePhoto = false;
      if (_pickedImageBytes != null) {
        final uploaded = await ref
            .read(apiClientProvider)
            .uploadImage(_pickedImageBytes!, _pickedImageName ?? 'group.png');
        photoUrl = uploaded;
        updatePhoto = true;
      } else if (_removePhoto) {
        photoUrl = '';
        updatePhoto = true;
      }

      await ref
          .read(groupControllerProvider.notifier)
          .updateGroup(
            eventId: widget.eventId,
            userId: widget.userId,
            groupName: widget.groupName,
            displayName: displayName,
            updateDisplayName: true,
            description: _descCtrl.text.trim(),
            photoUrl: photoUrl,
            updatePhoto: updatePhoto,
          );
      // Info panel reads eventGroupsProvider only — do not invalidate merch:
      // that forces a full-screen loading scaffold and resets the active tab.
      ref.invalidate(eventGroupsProvider(widget.eventId));
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(l10n.groupSaved)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.failedToSaveGroup(e.toString())),
          backgroundColor: errorColor,
        ),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasPreview = _previewUrl != null && _previewUrl!.isNotEmpty;
    return AlertDialog(
      title: Text(l10n.editGroup),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l10n.groupNameLabel,
                helperText: l10n.groupDisplayNameHelper,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: InputDecoration(
                labelText: l10n.groupDescription,
                hintText: l10n.groupDescriptionHint,
              ),
              maxLines: 4,
              enabled: !_saving,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.groupPhoto,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            if (hasPreview)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: double.infinity,
                  child: buildImage(
                    _previewUrl,
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                  ),
                ),
              )
            else
              Container(
                height: 80,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l10n.noGroupPhoto,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickImage,
                  icon: const Icon(Icons.image, size: 18),
                  label: Text(hasPreview ? l10n.changeImage : l10n.chooseImage),
                ),
                if (hasPreview) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _saving ? null : _clearImage,
                    child: Text(
                      l10n.remove,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.save),
        ),
      ],
    );
  }
}
