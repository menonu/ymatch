import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
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
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select Image Source'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Row(
              children: [
                Icon(Icons.photo_library),
                SizedBox(width: 12),
                Text('Gallery'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: const Row(
              children: [
                Icon(Icons.camera_alt),
                SizedBox(width: 12),
                Text('Camera'),
              ],
            ),
          ),
        ],
      ),
    );
    if (source == null) return;

    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 85,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _pickedImageBytes = bytes;
          _pickedImageName = image.name;
          // Store base64 for preview only
          _urlController.text = 'data:image/png;base64,${base64Encode(bytes)}';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
      }
    }
  }

  void _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    if (_selectedGroup == null || _selectedGroup!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or create an item group first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isAdding = true);

    try {
      // Upload image first if one was picked
      String photoUrl = _urlController.text.trim();
      if (_pickedImageBytes != null) {
        final apiClient = ref.read(apiClientProvider);
        final uploadedUrl = await apiClient.uploadImage(
          _pickedImageBytes!,
          _pickedImageName ?? 'image.png',
        );
        photoUrl = uploadedUrl;
      }

      await ref
          .read(merchControllerProvider.notifier)
          .addMerch(
            widget.eventId,
            name,
            photoUrl,
            _selectedGroup,
          );

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
            content: Text('Added "$name" successfully.'),
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
            content: Text('Failed to add "$name": $e'),
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: merchAsync.when(
        data: (merchList) {
          // Extract unique groups
          final Set<String> uniqueGroups = {};
          for (final item in merchList) {
            if (item.hasGroupName() && item.groupName.isNotEmpty) {
              uniqueGroups.add(item.groupName);
            }
          }
          uniqueGroups.addAll(_customGroups);
          final groups = uniqueGroups.toList()..sort(_naturalCompare);

          // Auto-select the first group if none is selected and groups exist
          if (_selectedGroup == null && groups.isNotEmpty) {
            _selectedGroup = groups.first;
          }

          // Filter existing items in the currently selected group to show as preview
          final itemsInSelectedGroup =
              merchList.where((item) {
                final gName = item.hasGroupName() && item.groupName.isNotEmpty
                    ? item.groupName
                    : null;
                return gName == _selectedGroup;
              }).toList()..sort(
                (a, b) => _naturalCompare(a.name, b.name),
              );

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
                      'Select Group',
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
                                label: Text(g),
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
                            label: const Text('New Group'),
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
                      decoration: const InputDecoration(
                        labelText: 'Item Name',
                        hintText: 'e.g., Rare Holo Card #1',
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
                                : const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_a_photo,
                                        color: Colors.grey,
                                        size: 28,
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Photo',
                                        style: TextStyle(
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
                                      ? 'Change Image'
                                      : 'Choose Image',
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
                                  child: const Text(
                                    'Remove',
                                    style: TextStyle(
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
                      label: Text(_isAdding ? 'Adding...' : 'Add Item'),
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
                  'Existing items in "${_selectedGroup ?? 'Uncategorized'}"',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: Colors.grey[600]),
                ),
              ),
              Expanded(
                child: itemsInSelectedGroup.isEmpty
                    ? Center(
                        child: Text(
                          'No items in this group yet.',
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
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showNewGroupDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Group Name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g., Keychains'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                setState(() {
                  _customGroups.add(val);
                  _selectedGroup = val;
                });
              }
              Navigator.pop(context);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
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
