/// Inventory export to text — pure formatting for the per-item-group
/// export feature (ADR 0007).
///
/// The export is rendered entirely client-side from the user's already-fetched
/// inventory ([`InventoryItem`] rows carry `merchName` + `groupName`). This
/// module is a pure function of (items, group, selection, format, labels) so it
/// is trivially unit-testable and has no widget/l10n dependency.
///
/// Shared rules (ADR 0007):
/// - Scope to a single `(groupName)`: items whose `groupName` does not match
///   are excluded.
/// - Exclude rows with `quantity <= 0` (matches the matching engine, which
///   only considers `quantity > 0`).
/// - Exclude rows with an empty `merchName`.
/// - Fixed status order: 所持 (HAVE) → 求 (WANT) → 譲 (TRADE).
/// - Items within a status are sorted alphabetically by name for stable diffs.
/// - Labels are supplied by the caller (from `.arb` `have`/`want`/`trade`),
///   so the function is locale-agnostic.
library;

import 'package:frontend/generated/models.pb.dart';

/// Output format for the export.
enum ExportFormat { basic, csv, markdown }

/// Selectable inventory statuses. Values are ordered 所持 → 求 → 譲; code below
/// relies on [ExportStatus.values] iterating in this order.
enum ExportStatus { have, want, trade }

/// Localized section labels, supplied by the caller from `.arb`.
class ExportLabels {
  final String have;
  final String want;
  final String trade;

  const ExportLabels({
    required this.have,
    required this.want,
    required this.trade,
  });

  String labelFor(ExportStatus s) {
    switch (s) {
      case ExportStatus.have:
        return have;
      case ExportStatus.want:
        return want;
      case ExportStatus.trade:
        return trade;
    }
  }
}

const _statusForToken = {
  'HAVE': ExportStatus.have,
  'WANT': ExportStatus.want,
  'TRADE': ExportStatus.trade,
};

/// Render the user's inventory for [groupName] as text in the requested
/// [format], including only the [selected] statuses.
///
/// Lines are joined with `\n` (LF) in every format. `basic` omits a status line
/// entirely when it has no matching items (or is unchecked); `csv`/`markdown`
/// always emit their header (and `markdown` its separator row).
String exportInventoryText({
  required List<InventoryItem> items,
  required String groupName,
  required Set<ExportStatus> selected,
  required ExportFormat format,
  required ExportLabels labels,
}) {
  // Bucket the matching items by status, sorting each bucket by name.
  // `LinkedHashMap` preserves insertion order (have → want → trade).
  final buckets = <ExportStatus, List<({String name, int qty})>>{
    for (final s in ExportStatus.values) s: [],
  };
  for (final item in items) {
    if (!item.hasGroupName() || item.groupName != groupName) continue;
    if (item.quantity <= 0) continue;
    final name = item.hasMerchName() ? item.merchName : '';
    if (name.isEmpty) continue;
    final status = _statusForToken[item.status];
    if (status == null) continue;
    if (!selected.contains(status)) continue;
    buckets[status]!.add((name: name, qty: item.quantity));
  }
  for (final bucket in buckets.values) {
    bucket.sort((a, b) => a.name.compareTo(b.name));
  }

  switch (format) {
    case ExportFormat.basic:
      return _renderBasic(buckets, selected, labels);
    case ExportFormat.csv:
      return _renderCsv(buckets, selected, labels);
    case ExportFormat.markdown:
      return _renderMarkdown(buckets, selected, labels);
  }
}

String _renderBasic(
  Map<ExportStatus, List<({String name, int qty})>> buckets,
  Set<ExportStatus> selected,
  ExportLabels labels,
) {
  final lines = <String>[];
  for (final s in ExportStatus.values) {
    if (!selected.contains(s)) continue;
    final bucket = buckets[s]!;
    if (bucket.isEmpty) continue;
    final rendered = bucket
        .map((e) => e.qty == 1 ? e.name : '${e.name}*${e.qty}')
        .join(', ');
    lines.add('${labels.labelFor(s)}: $rendered');
  }
  return lines.join('\n');
}

String _renderCsv(
  Map<ExportStatus, List<({String name, int qty})>> buckets,
  Set<ExportStatus> selected,
  ExportLabels labels,
) {
  final rows = <String>['status,item,quantity'];
  for (final s in ExportStatus.values) {
    if (!selected.contains(s)) continue;
    final label = labels.labelFor(s);
    for (final e in buckets[s]!) {
      rows.add('${_csvCell(label)},${_csvCell(e.name)},${e.qty}');
    }
  }
  return rows.join('\n');
}

String _renderMarkdown(
  Map<ExportStatus, List<({String name, int qty})>> buckets,
  Set<ExportStatus> selected,
  ExportLabels labels,
) {
  final rows = <String>['| status | item | qty |', '|--------|------|-----|'];
  for (final s in ExportStatus.values) {
    if (!selected.contains(s)) continue;
    final label = labels.labelFor(s);
    for (final e in buckets[s]!) {
      rows.add('| ${_mdCell(label)} | ${_mdCell(e.name)} | ${e.qty} |');
    }
  }
  return rows.join('\n');
}

/// Quote a CSV field per RFC 4180: wrap in double quotes when it contains a
/// comma, double-quote, or newline; double any embedded double-quote. (Line
/// terminator is LF, matching the other formats and clipboard use.)
String _csvCell(String field) {
  if (field.contains(',') || field.contains('"') || field.contains('\n')) {
    return '"${field.replaceAll('"', '""')}"';
  }
  return field;
}

/// Escape a markdown table cell so a `|` in the content is not parsed as a
/// column separator (GFM).
String _mdCell(String field) => field.replaceAll('|', '\\|');
