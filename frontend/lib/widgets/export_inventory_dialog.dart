/// Export-inventory dialog (ADR 0007).
///
/// Lets the user pick which of 所持 / 求 / 譲 to include and a text format,
/// previews the result, and copies it to the clipboard. The inventory is read
/// from [inventoryProvider] for the current user and filtered to [rawGroup]
/// (empty string for the synthetic "Other items" bucket).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/inventory_export.dart';

class ExportInventoryDialog extends ConsumerStatefulWidget {
  final User user;
  final String displayGroupName;
  final String rawGroup;

  const ExportInventoryDialog({
    super.key,
    required this.user,
    required this.displayGroupName,
    required this.rawGroup,
  });

  @override
  ConsumerState<ExportInventoryDialog> createState() =>
      _ExportInventoryDialogState();
}

class _ExportInventoryDialogState extends ConsumerState<ExportInventoryDialog> {
  bool _includeHave = true;
  bool _includeWant = true;
  bool _includeTrade = true;
  ExportFormat _format = ExportFormat.basic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final inventoryAsync = ref.watch(inventoryProvider(widget.user.id));
    final labels = ExportLabels(
      have: l10n.have,
      want: l10n.want,
      trade: l10n.trade,
    );

    final selected = {
      if (_includeHave) ExportStatus.have,
      if (_includeWant) ExportStatus.want,
      if (_includeTrade) ExportStatus.trade,
    };

    final text = inventoryAsync.maybeWhen(
      data: (items) => exportInventoryText(
        items: items,
        groupName: widget.rawGroup,
        selected: selected,
        format: _format,
        labels: labels,
      ),
      orElse: () => '',
    );

    return AlertDialog(
      title: Text('${l10n.exportInventoryTitle} — ${widget.displayGroupName}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status checkboxes — 所持 / 求 / 譲 (ADR 0007).
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _includeHave,
                title: Text(l10n.have),
                onChanged: (v) =>
                    setState(() => _includeHave = v ?? _includeHave),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _includeWant,
                title: Text(l10n.want),
                onChanged: (v) =>
                    setState(() => _includeWant = v ?? _includeWant),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _includeTrade,
                title: Text(l10n.trade),
                onChanged: (v) =>
                    setState(() => _includeTrade = v ?? _includeTrade),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.exportFormatLabel,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              DropdownButton<ExportFormat>(
                value: _format,
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                    value: ExportFormat.basic,
                    child: Text(l10n.exportFormatBasic),
                  ),
                  DropdownMenuItem(
                    value: ExportFormat.csv,
                    child: Text(l10n.exportFormatCsv),
                  ),
                  DropdownMenuItem(
                    value: ExportFormat.markdown,
                    child: Text(l10n.exportFormatMarkdown),
                  ),
                ],
                onChanged: (v) => setState(() => _format = v ?? _format),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 200),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    text.isEmpty ? l10n.exportEmpty : text,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: text.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    this.context,
                  ).showSnackBar(SnackBar(content: Text(l10n.exportCopied)));
                  Navigator.of(this.context).pop();
                },
          child: Text(l10n.exportCopy),
        ),
      ],
    );
  }
}
