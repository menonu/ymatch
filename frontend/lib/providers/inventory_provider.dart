import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../models/models.dart';

// --- Inventory ---
// --- Inventory Notifier (Optimistic Updates) ---
class UserInventoryNotifier
    extends FamilyAsyncNotifier<List<InventoryItem>, int> {
  @override
  Future<List<InventoryItem>> build(int arg) async {
    final client = ref.watch(apiClientProvider);
    final json = await client.get('/api/v1/user/$arg/inventory');
    return (json as List)
        .map((e) => InventoryItem()..mergeFromProto3Json(e))
        .toList();
  }

  Future<void> updateItem(int merchId, String status, int quantity) async {
    final userId = arg;
    final previousState = state;

    // 1. Optimistic Update
    if (state.hasValue) {
      final currentList = state.value!;
      bool found = false;
      final newList = currentList.map((item) {
        if (item.merchId == merchId && item.status == status) {
          found = true;
          // clone is deprecated, instantiate a new one and copy props
          final updated = InventoryItem()
            ..id = item.id
            ..userId = item.userId
            ..merchId = item.merchId
            ..status = item.status
            ..quantity = quantity
            ..merchName = item.merchName;
          if (item.hasIsDeleted()) updated.isDeleted = item.isDeleted;
          return updated;
        }
        return item;
      }).toList();

      if (!found && quantity > 0) {
        newList.add(
          InventoryItem()
            ..id = 0
            ..userId = userId
            ..merchId = merchId
            ..status = status
            ..quantity = quantity
            ..merchName = '',
        );
      }
      // filter out 0 quantity if desired, but for now just keep
      state = AsyncValue.data(newList);
    }

    // 2. Network Call
    try {
      final client = ref.read(apiClientProvider);
      final payload = UpdateInventoryRequest()
        ..userId = userId
        ..merchId = merchId
        ..status = status
        ..quantity = quantity;
      await client.post(
        '/api/v1/user/inventory',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      // Do NOT invalidate yet, let the user keep clicking.
      // We can refresh later or on some other event if needed.
    } catch (e) {
      // Roll back the optimistic state, then rethrow so callers can
      // react to the failure (e.g. the "Want All Missing" loop in
      // event_detail_screen.dart only counts items that were actually
      // saved). See #239 — previously this was swallowed silently.
      state = previousState;
      debugPrint('updateItem($merchId, $status, $quantity) failed: $e');
      rethrow;
    }
  }
}

final inventoryProvider =
    AsyncNotifierProviderFamily<
      UserInventoryNotifier,
      List<InventoryItem>,
      int
    >(() {
      return UserInventoryNotifier();
    });
