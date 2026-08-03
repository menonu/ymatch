import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../models/models.dart';
import 'auth_provider.dart';
import 'mutation_controller.dart';

// --- Merchandise (Family provider by event_id) ---
final merchProvider = FutureProvider.family<List<Merchandise>, int>((
  ref,
  eventId,
) async {
  final client = ref.watch(apiClientProvider);
  final user = ref.watch(currentUserProvider);
  String url = '/api/v1/events/$eventId/merch';
  if (user != null) {
    url += '?user_id=${user.id}';
  }
  final json = await client.get(url);
  return (json as List)
      .map((e) => Merchandise()..mergeFromProto3Json(e))
      .toList();
});

// --- My event role (#366 / #442) ---
// The caller's effective standing on a single event, used to gate the Add Merch
// button and member-management UI without reading the denormalized `User.role`.
// `canCreateMerch` / `canManageEditors` are the exact RBAC decisions the
// backend enforces, so the gate is not a client-side re-derivation. Returns
// `null` when there is no logged-in user or the fetch fails — both leave gated
// UI hidden (the safe default; the backend 403 remains the defense-in-depth
// backstop on tap).
final myEventRoleProvider = FutureProvider.autoDispose
    .family<MyEventRoleResponse?, int>((ref, eventId) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return null;
      final client = ref.watch(apiClientProvider);
      try {
        final json = await client.get(
          '/api/v1/events/$eventId/my-role?user_id=${user.id}',
        );
        if (json is! Map<String, dynamic>) return null;
        return MyEventRoleResponse()..mergeFromProto3Json(json);
      } catch (_) {
        return null;
      }
    });

/// Caller's standing on a single item group (#443). Key is `(eventId, groupName)`.
/// Returns null when not logged in, synthetic/missing group, or fetch fails —
/// gated UI stays hidden (backend 403 is the defense-in-depth backstop).
final myGroupRoleProvider = FutureProvider.autoDispose
    .family<MyGroupRoleResponse?, ({int eventId, String groupName})>((
      ref,
      key,
    ) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return null;
      if (key.groupName.isEmpty) return null;
      final client = ref.watch(apiClientProvider);
      try {
        final encoded = Uri.encodeComponent(key.groupName);
        final json = await client.get(
          '/api/v1/events/${key.eventId}/groups/$encoded/my-role?user_id=${user.id}',
        );
        if (json is! Map<String, dynamic>) return null;
        return MyGroupRoleResponse()..mergeFromProto3Json(json);
      } catch (_) {
        return null;
      }
    });

/// Directory of users for pickers (self-service member UI, #442).
/// #491: requires active caller; lean DTO without secrets for non-staff.
final usersDirectoryProvider = FutureProvider<List<User>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final json = await client.get('/api/v1/users?user_id=${user.id}');
  return (json as List).map((e) => User()..mergeFromProto3Json(e)).toList();
});

/// Merch create/update/delete mutations (#227 / #299 / #266).
///
/// #498: concurrent mutations use [ConcurrentMutationMixin]; failures always
/// rethrow so callers detect outcome from the returned [Future].
class MerchController extends StateNotifier<AsyncValue<void>>
    with ConcurrentMutationMixin {
  final ApiClient client;
  MerchController(this.client) : super(const AsyncValue.data(null));

  Future<void> addMerch(
    int eventId,
    String name,
    String photoUrl, [
    String? groupName,
    int? creatorId,
    String? status,
  ]) {
    // #227: rethrow (via runMutation) so the caller can show a real error
    // message instead of a misleading "Added successfully" SnackBar on 422.
    return runMutation(() async {
      final payload = CreateMerchRequest()
        ..name = name
        ..photoUrl = photoUrl;
      if (groupName != null && groupName.isNotEmpty) {
        payload.groupName = groupName;
      }
      if (creatorId != null) payload.creatorId = creatorId;
      if (status != null) payload.status = status;

      await client.post(
        '/api/v1/events/$eventId/merch',
        payload.toProto3Json() as Map<String, dynamic>,
      );
    });
  }

  Future<void> updateMerch(
    int eventId,
    int merchId,
    int userId, {
    String? name,
    String? photoUrl,
    String? groupName,
  }) {
    // #299: rethrow so the edit dialog can surface backend errors.
    return runMutation(() async {
      final payload = UpdateMerchRequest()..userId = userId;
      if (name != null) payload.name = name;
      if (photoUrl != null) payload.photoUrl = photoUrl;
      if (groupName != null) payload.groupName = groupName;
      await client.put(
        '/api/v1/events/$eventId/merch/$merchId',
        payload.toProto3Json() as Map<String, dynamic>,
      );
    });
  }

  Future<void> deleteMerchByCreator(int eventId, int merchId, int userId) {
    // #266: rethrow so the delete dialog can surface a failure SnackBar.
    return runMutation(() async {
      await client.delete(
        '/api/v1/events/$eventId/merch/$merchId?user_id=$userId',
      );
    });
  }
}

final merchControllerProvider =
    StateNotifierProvider<MerchController, AsyncValue<void>>((ref) {
      return MerchController(ref.watch(apiClientProvider));
    });
