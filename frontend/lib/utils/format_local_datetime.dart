/// Format an ISO-8601 timestamp for UI display in the **device local** timezone.
///
/// Returns `yyyy/MM/dd HH:mm` (zero-padded), or `null` when [isoDate] is empty
/// or not parseable so callers can omit the line rather than show a placeholder.
///
/// Matches are stored/returned as UTC (RFC 3339); always convert with
/// [DateTime.toLocal] before rendering so users see wall-clock local time (#476).
String? formatLocalDateTime(String isoDate) {
  if (isoDate.isEmpty) return null;
  try {
    final local = DateTime.parse(isoDate).toLocal();
    final y = local.year.toString();
    final mo = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$y/$mo/$d $h:$mi';
  } catch (_) {
    return null;
  }
}

/// Compare two optional ISO-8601 timestamps for **latest first** ordering.
///
/// Missing or unparseable timestamps sort after valid ones. When both are
/// missing/equal, [fallback] (typically match id) breaks ties.
int compareIsoDateTimeDesc(String? a, String? b, {int Function()? fallback}) {
  final aDt = (a != null && a.isNotEmpty) ? DateTime.tryParse(a) : null;
  final bDt = (b != null && b.isNotEmpty) ? DateTime.tryParse(b) : null;
  if (aDt == null && bDt == null) {
    return fallback?.call() ?? 0;
  }
  if (aDt == null) return 1;
  if (bDt == null) return -1;
  final cmp = bDt.compareTo(aDt);
  if (cmp != 0) return cmp;
  return fallback?.call() ?? 0;
}
