import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../models/models.dart';
import 'auth_provider.dart';
import 'member_models.dart';
import 'mutation_controller.dart';

// --- Admin ---
class AdminGroup {
  const AdminGroup({
    required this.eventId,
    required this.eventName,
    required this.groupName,
    this.displayName,
    this.creatorId,
    this.creatorUsername,
    required this.itemCount,
  });

  final int eventId;
  final String eventName;
  final String groupName;

  /// Cosmetic label; UI falls back to [groupName] when null/empty (#430).
  final String? displayName;

  /// Group ownership short-circuit (`created_by`); null if unowned (#432).
  final int? creatorId;

  /// Username of [creatorId] when set (#432).
  final String? creatorUsername;
  final int itemCount;

  /// User-visible label: [displayName] when set, otherwise the key (#430).
  String get label {
    final d = displayName;
    if (d != null && d.isNotEmpty) return d;
    return groupName;
  }

  /// Display string for the group creator on the admin Groups tab (#432).
  String get creatorLabel {
    final name = creatorUsername;
    if (name != null && name.isNotEmpty) {
      return creatorId != null ? '$name ($creatorId)' : name;
    }
    if (creatorId != null) return 'ID $creatorId';
    return 'Unowned';
  }

  factory AdminGroup.fromJson(Map<String, dynamic> json) => AdminGroup(
    eventId: json['eventId'] as int,
    eventName: json['eventName'] as String,
    groupName: json['groupName'] as String,
    displayName: json['displayName'] as String?,
    creatorId: json['creatorId'] as int?,
    creatorUsername: json['creatorUsername'] as String?,
    itemCount: json['itemCount'] as int,
  );
}

final adminGroupsProvider = FutureProvider<List<AdminGroup>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  // #491: admin catalog lists require staff + user_id.
  final json = await client.get('/api/v1/admin/groups?user_id=${user.id}');
  return (json as List)
      .map((e) => AdminGroup.fromJson(e as Map<String, dynamic>))
      .toList();
});

final adminMerchProvider = FutureProvider<List<Merchandise>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final json = await client.get('/api/v1/admin/merch?user_id=${user.id}');
  return (json as List)
      .map((e) => Merchandise()..mergeFromProto3Json(e))
      .toList();
});

final adminMatchesProvider = FutureProvider<List<TradeMatch>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final json = await client.get('/api/v1/admin/matches?user_id=${user.id}');
  return (json as List)
      .map((e) => TradeMatch()..mergeFromProto3Json(e))
      .toList();
});

// --- Admin Users ---
final adminUsersProvider = FutureProvider<List<User>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  // Staff path of GET /users (user.read) returns role + ban fields (#491).
  final json = await client.get('/api/v1/users?user_id=${user.id}');
  return (json as List).map((e) => User()..mergeFromProto3Json(e)).toList();
});

/// Admin mutations. Failures rethrow (#266); concurrent calls are generation-
/// gated via [ConcurrentMutationMixin] (#498).
class AdminController extends StateNotifier<AsyncValue<void>>
    with ConcurrentMutationMixin {
  final ApiClient client;
  AdminController(this.client) : super(const AsyncValue.data(null));

  Future<void> banUser(
    int targetUserId,
    int adminUserId, {
    String? reason,
    String? bannedUntil,
  }) {
    return runMutation(() async {
      final payload = BanUserRequest();
      if (reason != null) payload.reason = reason;
      if (bannedUntil != null) payload.bannedUntil = bannedUntil;
      await client.post(
        '/api/v1/admin/users/$targetUserId/ban?user_id=$adminUserId',
        payload.toProto3Json() as Map<String, dynamic>,
      );
    });
  }

  Future<void> unbanUser(int targetUserId, int adminUserId) {
    return runMutation(() async {
      await client.post(
        '/api/v1/admin/users/$targetUserId/unban?user_id=$adminUserId',
        {},
      );
    });
  }

  Future<void> updateUserRole(int targetUserId, int adminUserId, String role) {
    return runMutation(() async {
      final payload = UpdateUserRoleRequest()..role = role;
      await client.post(
        '/api/v1/admin/users/$targetUserId/role?user_id=$adminUserId',
        payload.toProto3Json() as Map<String, dynamic>,
      );
    });
  }

  Future<void> publishEvent(int eventId, int userId) {
    return runMutation(() async {
      final payload = UserActionRequest()..userId = userId;
      await client.post(
        '/api/v1/events/$eventId/publish',
        payload.toProto3Json() as Map<String, dynamic>,
      );
    });
  }

  Future<void> publishMerch(int eventId, int merchId, int userId) {
    return runMutation(() async {
      final payload = UserActionRequest()..userId = userId;
      await client.post(
        '/api/v1/events/$eventId/merch/$merchId/publish',
        payload.toProto3Json() as Map<String, dynamic>,
      );
    });
  }

  Future<void> deleteEvent(int eventId, int userId) {
    return runMutation(() async {
      await client.delete('/api/v1/admin/events/$eventId?user_id=$userId');
    });
  }

  Future<void> deleteMerch(int merchId, int userId) {
    return runMutation(() async {
      await client.delete('/api/v1/admin/merch/$merchId?user_id=$userId');
    });
  }

  Future<void> deleteMatch(int matchId, int userId) {
    return runMutation(() async {
      await client.delete('/api/v1/admin/matches/$matchId?user_id=$userId');
    });
  }

  /// Soft-remove an item group (`DELETE /admin/events/:id/groups/:name`) (#496).
  ///
  /// Group name is URL-encoded so keys with `/` and other reserved characters
  /// round-trip correctly (same encoding as [transferGroupCreator]).
  Future<void> deleteGroup(int eventId, String groupName, int userId) {
    return runMutation(() async {
      final encoded = Uri.encodeComponent(groupName);
      await client.delete(
        '/api/v1/admin/events/$eventId/groups/$encoded?user_id=$userId',
      );
    });
  }

  /// Transfer event ownership (`PUT /admin/events/:id/creator`) (#432).
  Future<void> transferEventCreator(
    int eventId,
    int adminUserId,
    int newCreatorId,
  ) {
    return runMutation(() async {
      await client.put(
        '/api/v1/admin/events/$eventId/creator?user_id=$adminUserId',
        {'newCreatorId': newCreatorId},
      );
    });
  }

  /// Transfer group ownership (`PUT /admin/events/:id/groups/:name/creator`) (#432).
  Future<void> transferGroupCreator(
    int eventId,
    String groupName,
    int adminUserId,
    int newCreatorId,
  ) {
    return runMutation(() async {
      final encoded = Uri.encodeComponent(groupName);
      await client.put(
        '/api/v1/admin/events/$eventId/groups/$encoded/creator?user_id=$adminUserId',
        {'newCreatorId': newCreatorId},
      );
    });
  }

  /// List event members via admin path (#432).
  Future<List<EventMemberInfo>> listEventMembers(
    int eventId,
    int adminUserId,
  ) async {
    final json = await client.get(
      '/api/v1/admin/events/$eventId/members?user_id=$adminUserId',
    );
    final members = (json as Map<String, dynamic>)['members'] as List? ?? [];
    return members
        .map((e) => EventMemberInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Assign event editor via admin path (#432).
  Future<void> assignEventEditor(
    int eventId,
    int targetUserId,
    int adminUserId,
  ) {
    return runMutation(() async {
      await client.post(
        '/api/v1/admin/events/$eventId/members/$targetUserId?user_id=$adminUserId',
        {},
      );
    });
  }

  /// Revoke event editor via admin path (#432). Never removes creator role.
  Future<void> revokeEventEditor(
    int eventId,
    int targetUserId,
    int adminUserId,
  ) {
    return runMutation(() async {
      await client.delete(
        '/api/v1/admin/events/$eventId/members/$targetUserId?user_id=$adminUserId',
      );
    });
  }
}

final adminControllerProvider =
    StateNotifierProvider<AdminController, AsyncValue<void>>((ref) {
      return AdminController(ref.watch(apiClientProvider));
    });
