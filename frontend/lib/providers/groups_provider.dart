import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../models/models.dart';

// --- Merchandise groups (#128) ---
// Group metadata (description + creator) is a first-class entity separate from
// the merch list. Loaded independently so the EventDetailScreen info panel and
// bottom edit control can update without refetching every item.
final eventGroupsProvider = FutureProvider.autoDispose
    .family<List<MerchandiseGroup>, int>((ref, eventId) async {
      final client = ref.watch(apiClientProvider);
      final json = await client.get('/api/v1/events/$eventId/groups');
      if (json is! Map<String, dynamic>) return [];
      final response = ListGroupsResponse()..mergeFromProto3Json(json);
      return response.groups;
    });

class GroupController extends StateNotifier<AsyncValue<void>> {
  final ApiClient client;
  GroupController(this.client) : super(const AsyncValue.data(null));

  Future<MerchandiseGroup> createGroup({
    required int eventId,
    required int userId,
    required String groupName,
    String? description,
    String? photoUrl,
  }) async {
    state = const AsyncValue.loading();
    try {
      final payload = CreateGroupRequest()
        ..eventId = eventId
        ..userId = userId
        ..groupName = groupName;
      if (description != null && description.isNotEmpty) {
        payload.description = description;
      }
      if (photoUrl != null && photoUrl.isNotEmpty) {
        payload.photoUrl = photoUrl;
      }
      final json = await client.post(
        '/api/v1/events/$eventId/groups',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      state = const AsyncValue.data(null);
      return MerchandiseGroup()
        ..mergeFromProto3Json(json as Map<String, dynamic>);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<MerchandiseGroup> updateGroup({
    required int eventId,
    required int userId,
    required String groupName,
    // Cosmetic label (#425). Always sent by the edit dialog (the name field is
    // never empty); empty string clears display_name → UI falls back to the
    // immutable group_name key.
    String? displayName,
    String? description,
    // null = leave photo unchanged; non-null (including '') = set/clear (#404).
    String? photoUrl,
    bool updatePhoto = false,
    bool updateDisplayName = false,
  }) async {
    state = const AsyncValue.loading();
    try {
      final payload = UpdateGroupRequest()
        ..eventId = eventId
        ..userId = userId
        ..groupName = groupName;
      // Always send description so clearing the field is possible.
      payload.description = description ?? '';
      if (updateDisplayName) {
        payload.displayName = displayName ?? '';
      }
      if (updatePhoto) {
        payload.photoUrl = photoUrl ?? '';
      }
      final encodedName = Uri.encodeComponent(groupName);
      final json = await client.put(
        '/api/v1/events/$eventId/groups/$encodedName',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      state = const AsyncValue.data(null);
      return MerchandiseGroup()
        ..mergeFromProto3Json(json as Map<String, dynamic>);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

final groupControllerProvider =
    StateNotifierProvider<GroupController, AsyncValue<void>>((ref) {
      return GroupController(ref.watch(apiClientProvider));
    });
