import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

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

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  void _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isAdding = true);

    try {
      await ref
          .read(merchControllerProvider.notifier)
          .addMerch(
            widget.eventId,
            name,
            _urlController.text.trim(),
            _selectedGroup,
          );

      // Clear inputs for continuous adding, but KEEP the selected group!
      _nameController.clear();
      _urlController.clear();

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
        title: const Text('Add Merchandise'),
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
          final groups = uniqueGroups.toList()..sort();

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
                (a, b) => b.id.compareTo(a.id),
              ); // Newest first for the preview

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
                    TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: 'Photo URL (Optional)',
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
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
                              child:
                                  item.hasPhotoUrl() && item.photoUrl.isNotEmpty
                                  ? Image.network(
                                      item.photoUrl,
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Icon(Icons.image_outlined),
                                    )
                                  : Container(
                                      width: 40,
                                      height: 40,
                                      color: Colors.grey[200],
                                      child: const Icon(
                                        Icons.image_outlined,
                                        size: 20,
                                        color: Colors.grey,
                                      ),
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
}
