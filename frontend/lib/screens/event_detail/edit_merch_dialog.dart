library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../utils/image_helper.dart';

/// Dialog for editing a merch item's name and image (#205).
///
/// The backend `PUT /events/:eventId/merch/:merchId` already accepts `name`
/// and `photo_url`; the previous UI only exposed name editing. This dialog
/// reuses the same image-pick + upload flow as `AddMerchScreen` so a creator
/// can also replace the item's photo. The `photoUrl` is sent only when a new
/// image was picked, so leaving the image untouched does not clobber it.
class EditMerchDialog extends ConsumerStatefulWidget {
  final int eventId;
  final Merchandise item;

  const EditMerchDialog({super.key, required this.eventId, required this.item});

  @override
  ConsumerState<EditMerchDialog> createState() => _EditMerchDialogState();
}

class _EditMerchDialogState extends ConsumerState<EditMerchDialog> {
  late final TextEditingController _nameCtrl;
  // Preview URL for a newly picked image (base64 data URI); null means "show
  // the item's existing photo".
  String? _previewUrl;
  List<int>? _pickedImageBytes;
  String? _pickedImageName;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.item.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await pickMerchImage(context);
    if (picked != null) {
      setState(() {
        _pickedImageBytes = picked.bytes;
        _pickedImageName = picked.name;
        _previewUrl = picked.previewUrl;
      });
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _saving = true);
    try {
      // Only upload + send photoUrl when a new image was picked, so an
      // unchanged image is not overwritten with an empty/stale value.
      String? newPhotoUrl;
      if (_pickedImageBytes != null) {
        newPhotoUrl = await ref
            .read(apiClientProvider)
            .uploadImage(
              _pickedImageBytes!,
              _pickedImageName ?? 'image.png',
              userId: user.id,
            );
      }

      await ref
          .read(merchControllerProvider.notifier)
          .updateMerch(
            widget.eventId,
            widget.item.id,
            user.id,
            name: newName,
            photoUrl: newPhotoUrl,
          );
      ref.invalidate(merchProvider(widget.eventId));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // #299: updateMerch rethrows on failure (e.g. a duplicate-name 400).
      // Surface the backend error instead of silently closing the dialog.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.failedToUpdateItem(newName, e.toString())),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentPhotoUrl = widget.item.hasPhotoUrl()
        ? widget.item.photoUrl
        : null;
    return AlertDialog(
      title: Text(l10n.editItem),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 120,
                  height: 120,
                  child: buildImage(
                    _previewUrl ?? currentPhotoUrl,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _saving ? null : _pickImage,
                icon: const Icon(Icons.add_a_photo),
                label: Text(l10n.changeImage),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: InputDecoration(hintText: l10n.editItemNameHint),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
