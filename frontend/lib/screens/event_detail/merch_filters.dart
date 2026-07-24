/// Inventory view / filter modes and pure helpers for [EventDetailScreen] (#494).
///
/// Providers are keyed by [eventId] so prefs do not leak across events.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ViewMode { detailed, grid, list }

/// Per-event layout mode (detailed / grid / compact list).
final viewModeProvider = StateProvider.family<ViewMode, int>(
  (ref, eventId) => ViewMode.detailed,
);

enum MerchFilter { all, have, want, trade, missing }

/// Per-event merch quantity filter (#472).
final merchFilterProvider = StateProvider.family<MerchFilter, int>(
  (ref, eventId) => MerchFilter.all,
);

enum InventoryDisplayMode { have, wantTrade, trade, all }

/// Per-event which inventory steppers to show (#472).
final inventoryDisplayModeProvider =
    StateProvider.family<InventoryDisplayMode, int>(
      (ref, eventId) => InventoryDisplayMode.all,
    );

/// Per-event item name search query (auto-disposed when unused).
final itemSearchQueryProvider = StateProvider.autoDispose.family<String, int>(
  (ref, eventId) => '',
);

/// Whether [item] inventory quantities pass [filter] (#472).
///
/// [missing] keeps pre-existing semantics: HAVE == 0 && WANT == 0 (TRADE is
/// ignored). TRADE-only stock therefore still matches Missing.
bool matchesMerchFilter(
  MerchFilter filter, {
  required int have,
  required int want,
  required int trade,
}) {
  switch (filter) {
    case MerchFilter.all:
      return true;
    case MerchFilter.have:
      return have > 0;
    case MerchFilter.want:
      return want > 0;
    case MerchFilter.trade:
      return trade > 0;
    case MerchFilter.missing:
      return have == 0 && want == 0;
  }
}

/// Which inventory steppers to show for [mode] (#472).
({bool showHave, bool showWant, bool showTrade}) inventoryDisplayFlags(
  InventoryDisplayMode mode,
) {
  switch (mode) {
    case InventoryDisplayMode.have:
      return (showHave: true, showWant: false, showTrade: false);
    case InventoryDisplayMode.wantTrade:
      return (showHave: false, showWant: true, showTrade: true);
    case InventoryDisplayMode.trade:
      return (showHave: false, showWant: false, showTrade: true);
    case InventoryDisplayMode.all:
      return (showHave: true, showWant: true, showTrade: true);
  }
}

/// Sum of HAVE / WANT / TRADE quantities across a merchandise group (#508).
///
/// Totals cover **items currently shown in the group** (after search + merch
/// filter). Soft-deleted rows that still appear in the list contribute their
/// displayed quantities so the card matches visible steppers.
class GroupInventoryTotals {
  const GroupInventoryTotals({
    required this.totalHave,
    required this.totalWant,
    required this.totalTrade,
  });

  final int totalHave;
  final int totalWant;
  final int totalTrade;

  static const zero = GroupInventoryTotals(
    totalHave: 0,
    totalWant: 0,
    totalTrade: 0,
  );

  /// Sum inventory quantities for each merchandise id in [merchIds].
  ///
  /// [lookup] is merchId → status → quantity (same map built on the event
  /// detail screen). Missing ids/statuses count as 0.
  factory GroupInventoryTotals.fromMerchIds(
    Iterable<int> merchIds,
    Map<int, Map<String, int>> lookup,
  ) {
    var have = 0;
    var want = 0;
    var trade = 0;
    for (final id in merchIds) {
      final inv = lookup[id];
      if (inv == null) continue;
      have += inv['HAVE'] ?? 0;
      want += inv['WANT'] ?? 0;
      trade += inv['TRADE'] ?? 0;
    }
    return GroupInventoryTotals(
      totalHave: have,
      totalWant: want,
      totalTrade: trade,
    );
  }
}

/// Index of [initialGroupName] in [groupKeys], or 0 if absent/unknown (#406).
int resolveInitialGroupTabIndex(
  List<String> groupKeys,
  String? initialGroupName,
) {
  if (groupKeys.isEmpty) return 0;
  if (initialGroupName == null || initialGroupName.isEmpty) return 0;
  final i = groupKeys.indexOf(initialGroupName);
  return i >= 0 ? i : 0;
}

/// Natural sort: split digit/non-digit runs so "item2" < "item10".
int naturalCompare(String a, String b) {
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
