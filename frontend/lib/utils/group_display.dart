import '../models/models.dart';

/// The user-visible label for a group: its cosmetic `display_name` when set,
/// otherwise the internal `group_name` key (#425 / #466). The key is unchanged
/// by an "edit name" — only the rendered text swaps to `display_name`.
String groupDisplayNameFor(String groupKey, MerchandiseGroup? meta) {
  if (meta != null && meta.hasDisplayName() && meta.displayName.isNotEmpty) {
    return meta.displayName;
  }
  return groupKey;
}

/// [groupDisplayNameFor] resolved against a name → metadata map.
String groupDisplayName(
  String groupKey,
  Map<String, MerchandiseGroup> groupByName,
) => groupDisplayNameFor(groupKey, groupByName[groupKey]);

/// Resolve a display label when the API already returned an optional
/// display-name field (favorites, match cards) without full group metadata.
String groupLabel(String groupKey, String? displayName) {
  if (displayName != null && displayName.isNotEmpty) return displayName;
  return groupKey;
}
