import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/group_display.dart';
import '../utils/image_helper.dart';

class AddMerchScreen extends ConsumerStatefulWidget {
  final int eventId;

  const AddMerchScreen({super.key, required this.eventId});

  @override
  ConsumerState<AddMerchScreen> createState() => _AddMerchScreenState();
}

class _AddMerchScreenState extends ConsumerState<AddMerchScreen> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();

  String? _selectedGroup;
  bool _isAdding = false;
  final FocusNode _nameFocusNode = FocusNode();
  final Set<String> _customGroups = {};
  List<int>? _pickedImageBytes;
  String? _pickedImageName;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await pickMerchImage(context);
    if (picked != null) {
      setState(() {
        _pickedImageBytes = picked.bytes;
        _pickedImageName = picked.name;
        // Store base64 for preview only
        _urlController.text = picked.previewUrl;
      });
    }
  }

  void _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;

    if (_selectedGroup == null || _selectedGroup!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.selectGroupFirst),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isAdding = true);

    try {
      // Upload image first if one was picked
      String photoUrl = _urlController.text.trim();
      final user = ref.read(currentUserProvider);
      if (_pickedImageBytes != null) {
        if (user == null) {
          throw StateError('Must be signed in to upload images');
        }
        final apiClient = ref.read(apiClientProvider);
        final uploadedUrl = await apiClient.uploadImage(
          _pickedImageBytes!,
          _pickedImageName ?? 'image.png',
          userId: user.id,
        );
        photoUrl = uploadedUrl;
      }

      await ref
          .read(merchControllerProvider.notifier)
          .addMerch(widget.eventId, name, photoUrl, _selectedGroup, user?.id);

      // Clear inputs for continuous adding, but KEEP the selected group!
      _nameController.clear();
      _urlController.clear();
      _pickedImageBytes = null;
      _pickedImageName = null;

      // Request focus back to the name field to type the next item immediately
      _nameFocusNode.requestFocus();

      // Invalidate to refresh the underlying list and the preview on this screen
      ref.invalidate(merchProvider(widget.eventId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.addedSuccessfully(name)),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // #227: addMerch rethrows on failure. Show the real error so
      // the user knows the merch was NOT added (instead of the
      // previous "Added successfully" lie).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.failedToAdd(name, e.toString())),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final merchAsync = ref.watch(merchProvider(widget.eventId));
    // #466: load formal group rows so chips can show display_name while
    // selection / create-merch still use the immutable group_name key.
    final groupsAsync = ref.watch(eventGroupsProvider(widget.eventId));
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: merchAsync.when(
        data: (merchList) {
          final groupsMeta =
              groupsAsync.valueOrNull ?? const <MerchandiseGroup>[];
          final groupByName = <String, MerchandiseGroup>{
            for (final g in groupsMeta) g.groupName: g,
          };

          // Keys for chips: merch groups + formal groups + session custom names.
          final Set<String> uniqueGroups = {};
          for (final item in merchList) {
            if (item.hasGroupName() && item.groupName.isNotEmpty) {
              uniqueGroups.add(item.groupName);
            }
          }
          for (final g in groupsMeta) {
            if (g.groupName.isNotEmpty) uniqueGroups.add(g.groupName);
          }
          uniqueGroups.addAll(_customGroups);
          final groups = uniqueGroups.toList()..sort(_naturalCompare);

          // Auto-select the first group if none is selected and groups exist
          if (_selectedGroup == null && groups.isNotEmpty) {
            _selectedGroup = groups.first;
          }

          // Filter existing items in the currently selected group to show as preview
          final itemsInSelectedGroup = merchList.where((item) {
            final gName = item.hasGroupName() && item.groupName.isNotEmpty
                ? item.groupName
                : null;
            return gName == _selectedGroup;
          }).toList()..sort((a, b) => _naturalCompare(a.name, b.name));

          final selectedLabel = _selectedGroup == null
              ? l10n.uncategorized
              : groupDisplayName(_selectedGroup!, groupByName);

          return Column(
            children: [
              // --- FORM SECTION ---
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Group Selection (Chips)
                    Text(
                      l10n.selectGroup,
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ...groups.map(
                            (g) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                // #466: cosmetic label; selection value stays the key.
                                label: Text(groupDisplayName(g, groupByName)),
                                selected: _selectedGroup == g,
                                selectedColor: AppTheme.primaryColor.withValues(
                                  alpha: 0.1,
                                ),
                                checkmarkColor: AppTheme.primaryColor,
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedGroup = selected ? g : null;
                                  });
                                },
                              ),
                            ),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: Text(l10n.newGroup),
                            onPressed: _showNewGroupDialog,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Inputs
                    TextField(
                      controller: _nameController,
                      focusNode: _nameFocusNode,
                      decoration: InputDecoration(
                        labelText: l10n.itemName,
                        hintText: l10n.itemNameHint,
                      ),
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 12),
                    // Image picker (replaces URL text field)
                    Row(
                      children: [
                        // Preview
                        GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.grey.withValues(alpha: 0.4),
                              ),
                            ),
                            child: _urlController.text.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: buildImage(
                                      _urlController.text,
                                      width: 80,
                                      height: 80,
                                    ),
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.add_a_photo,
                                        color: Colors.grey,
                                        size: 28,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        l10n.photo,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _pickImage,
                                icon: const Icon(Icons.image, size: 18),
                                label: Text(
                                  _urlController.text.isNotEmpty
                                      ? l10n.changeImage
                                      : l10n.chooseImage,
                                ),
                              ),
                              if (_urlController.text.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _urlController.clear();
                                    });
                                  },
                                  child: Text(
                                    l10n.remove,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Add Button
                    ElevatedButton.icon(
                      icon: _isAdding
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add),
                      label: Text(_isAdding ? l10n.adding : l10n.addItem),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _isAdding ? null : _submit,
                    ),
                  ],
                ),
              ),

              // --- PREVIEW SECTION ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: Colors.grey[100],
                child: Text(
                  l10n.existingItemsInGroup(selectedLabel),
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: Colors.grey[600]),
                ),
              ),
              Expanded(
                child: itemsInSelectedGroup.isEmpty
                    ? Center(
                        child: Text(
                          l10n.noItemsInGroup,
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: itemsInSelectedGroup.length,
                        itemBuilder: (context, index) {
                          final item = itemsInSelectedGroup[index];
                          return ListTile(
                            dense: true,
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: buildImage(
                                item.hasPhotoUrl() ? item.photoUrl : null,
                                width: 40,
                                height: 40,
                              ),
                            ),
                            title: Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text(l10n.errorPrefix(e.toString()))),
      ),
    );
  }

  Future<void> _showNewGroupDialog() async {
    final createdName = await showDialog<String>(
      context: context,
      builder: (context) =>
          _NewGroupDialog(eventId: widget.eventId, customGroups: _customGroups),
    );
    if (createdName == null || !mounted) return;
    setState(() {
      _customGroups.add(createdName);
      _selectedGroup = createdName;
    });
  }

  static int _naturalCompare(String a, String b) {
    final regExp = RegExp(r'(\d+)|(\D+)');
    final partsA = regExp.allMatches(a).toList();
    final partsB = regExp.allMatches(b).toList();
    for (int i = 0; i < partsA.length && i < partsB.length; i++) {
      final pa = partsA[i].group(0)!;
      final pb = partsB[i].group(0)!;
      final na = int.tryParse(pa);
      final nb = int.tryParse(pb);
      int cmp;
      if (na != null && nb != null) {
        cmp = na.compareTo(nb);
      } else {
        cmp = pa.toLowerCase().compareTo(pb.toLowerCase());
      }
      if (cmp != 0) return cmp;
    }
    return a.length.compareTo(b.length);
  }
}

/// New-group dialog with optional description (#128).
/// Owns its [TextEditingController]s so dispose cannot race the route close.
class _NewGroupDialog extends ConsumerStatefulWidget {
  final int eventId;
  final Set<String> customGroups;

  const _NewGroupDialog({required this.eventId, required this.customGroups});

  @override
  ConsumerState<_NewGroupDialog> createState() => _NewGroupDialogState();
}

class _NewGroupDialogState extends ConsumerState<_NewGroupDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final val = _nameCtrl.text.trim();
    if (val.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;

    // Never re-POST create for an existing name — backend create is an upsert
    // that overwrites description without an ownership check. Await the groups
    // list so a still-loading provider cannot miss a row.
    final knownNames = <String>{...widget.customGroups};
    try {
      final groups = await ref.read(eventGroupsProvider(widget.eventId).future);
      for (final g in groups) {
        knownNames.add(g.groupName);
      }
    } catch (_) {
      // Fall back to merch chip names only.
    }
    final merchList = ref.read(merchProvider(widget.eventId)).valueOrNull;
    if (merchList != null) {
      for (final m in merchList) {
        if (m.hasGroupName() && m.groupName.isNotEmpty) {
          knownNames.add(m.groupName);
        }
      }
    }
    final alreadyExists = knownNames.contains(val);

    final user = ref.read(currentUserProvider);
    // Persist a brand-new group when logged in so it becomes a first-class
    // entity before any merch is added (#128).
    if (user != null && !alreadyExists) {
      setState(() => _saving = true);
      try {
        final desc = _descCtrl.text.trim();
        await ref
            .read(groupControllerProvider.notifier)
            .createGroup(
              eventId: widget.eventId,
              userId: user.id,
              groupName: val,
              description: desc.isEmpty ? null : desc,
            );
        ref.invalidate(eventGroupsProvider(widget.eventId));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.failedToSaveGroup(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        setState(() => _saving = false);
        return;
      }
    }

    if (!mounted) return;
    Navigator.pop(context, val);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.newGroupName),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: InputDecoration(hintText: l10n.newGroupHint),
              textInputAction: TextInputAction.next,
              enabled: !_saving,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: InputDecoration(
                labelText: l10n.groupDescription,
                hintText: l10n.groupDescriptionHint,
              ),
              maxLines: 3,
              enabled: !_saving,
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
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.set),
        ),
      ],
    );
  }
}
