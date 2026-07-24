import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../models/models.dart';

export 'member_models.dart';
export 'system_provider.dart';
export 'auth_provider.dart';
export 'events_provider.dart';
export 'merch_provider.dart';
export 'groups_provider.dart';
export 'inventory_provider.dart';

import 'auth_provider.dart';
import 'member_models.dart';

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

class AdminController extends StateNotifier<AsyncValue<void>> {
  final ApiClient client;
  AdminController(this.client) : super(const AsyncValue.data(null));

  Future<void> banUser(
    int targetUserId,
    int adminUserId, {
    String? reason,
    String? bannedUntil,
  }) async {
    state = const AsyncValue.loading();
    try {
      final payload = BanUserRequest();
      if (reason != null) payload.reason = reason;
      if (bannedUntil != null) payload.bannedUntil = bannedUntil;
      await client.post(
        '/api/v1/admin/users/$targetUserId/ban?user_id=$adminUserId',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // #266: rethrow so the admin UI can show failure feedback.
      rethrow;
    }
  }

  Future<void> unbanUser(int targetUserId, int adminUserId) async {
    state = const AsyncValue.loading();
    try {
      await client.post(
        '/api/v1/admin/users/$targetUserId/unban?user_id=$adminUserId',
        {},
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // #266: rethrow so the admin UI can show failure feedback.
      rethrow;
    }
  }

  Future<void> updateUserRole(
    int targetUserId,
    int adminUserId,
    String role,
  ) async {
    state = const AsyncValue.loading();
    try {
      final payload = UpdateUserRoleRequest()..role = role;
      await client.post(
        '/api/v1/admin/users/$targetUserId/role?user_id=$adminUserId',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // #266: rethrow so the admin UI can show failure feedback.
      rethrow;
    }
  }

  Future<void> publishEvent(int eventId, int userId) async {
    state = const AsyncValue.loading();
    try {
      final payload = UserActionRequest()..userId = userId;
      await client.post(
        '/api/v1/events/$eventId/publish',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // #266 / pr-review: rethrow for consistent mutation failure surfacing.
      rethrow;
    }
  }

  Future<void> publishMerch(int eventId, int merchId, int userId) async {
    state = const AsyncValue.loading();
    try {
      final payload = UserActionRequest()..userId = userId;
      await client.post(
        '/api/v1/events/$eventId/merch/$merchId/publish',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // #266 / pr-review: rethrow for consistent mutation failure surfacing.
      rethrow;
    }
  }

  Future<void> deleteEvent(int eventId, int userId) async {
    state = const AsyncValue.loading();
    try {
      await client.delete('/api/v1/admin/events/$eventId?user_id=$userId');
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // #266 / pr-review: rethrow for consistent mutation failure surfacing.
      rethrow;
    }
  }

  Future<void> deleteMerch(int merchId, int userId) async {
    state = const AsyncValue.loading();
    try {
      await client.delete('/api/v1/admin/merch/$merchId?user_id=$userId');
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // #266 / pr-review: rethrow for consistent mutation failure surfacing.
      rethrow;
    }
  }

  Future<void> deleteMatch(int matchId, int userId) async {
    state = const AsyncValue.loading();
    try {
      await client.delete('/api/v1/admin/matches/$matchId?user_id=$userId');
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // #266 / pr-review: rethrow for consistent mutation failure surfacing.
      rethrow;
    }
  }

  /// Soft-remove an item group (`DELETE /admin/events/:id/groups/:name`) (#496).
  ///
  /// Group name is URL-encoded so keys with `/` and other reserved characters
  /// round-trip correctly (same encoding as [transferGroupCreator]).
  Future<void> deleteGroup(int eventId, String groupName, int userId) async {
    state = const AsyncValue.loading();
    try {
      final encoded = Uri.encodeComponent(groupName);
      await client.delete(
        '/api/v1/admin/events/$eventId/groups/$encoded?user_id=$userId',
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Transfer event ownership (`PUT /admin/events/:id/creator`) (#432).
  Future<void> transferEventCreator(
    int eventId,
    int adminUserId,
    int newCreatorId,
  ) async {
    state = const AsyncValue.loading();
    try {
      await client.put(
        '/api/v1/admin/events/$eventId/creator?user_id=$adminUserId',
        {'newCreatorId': newCreatorId},
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Transfer group ownership (`PUT /admin/events/:id/groups/:name/creator`) (#432).
  Future<void> transferGroupCreator(
    int eventId,
    String groupName,
    int adminUserId,
    int newCreatorId,
  ) async {
    state = const AsyncValue.loading();
    try {
      final encoded = Uri.encodeComponent(groupName);
      await client.put(
        '/api/v1/admin/events/$eventId/groups/$encoded/creator?user_id=$adminUserId',
        {'newCreatorId': newCreatorId},
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
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
  ) async {
    state = const AsyncValue.loading();
    try {
      await client.post(
        '/api/v1/admin/events/$eventId/members/$targetUserId?user_id=$adminUserId',
        {},
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Revoke event editor via admin path (#432). Never removes creator role.
  Future<void> revokeEventEditor(
    int eventId,
    int targetUserId,
    int adminUserId,
  ) async {
    state = const AsyncValue.loading();
    try {
      await client.delete(
        '/api/v1/admin/events/$eventId/members/$targetUserId?user_id=$adminUserId',
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

final adminControllerProvider =
    StateNotifierProvider<AdminController, AsyncValue<void>>((ref) {
      return AdminController(ref.watch(apiClientProvider));
    });

// --- Matches ---
final matchesProvider = FutureProvider.family<List<TradeMatch>, int>((
  ref,
  userId,
) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/matches/user/$userId');
  return (json as List)
      .map((e) => TradeMatch()..mergeFromProto3Json(e))
      .toList();
});

final notificationCountsProvider =
    FutureProvider.family<NotificationCounts, int>((ref, userId) async {
      final client = ref.watch(apiClientProvider);
      final json = await client.get('/api/v1/matches/user/$userId/counts');
      return NotificationCounts()..mergeFromProto3Json(json);
    });

/// Owns the three match-lifecycle mutations used by the trades UI.
///
/// #241: centralizes request body construction (proto types),
/// `matchesProvider` + `notificationCountsProvider` invalidation, and
/// loading/error state so screens can `ref.listen` instead of duplicating
/// try/catch + SnackBar + invalidate at each call site.
class MatchController extends StateNotifier<AsyncValue<void>> {
  final ApiClient client;
  final Ref ref;

  MatchController(this.client, this.ref) : super(const AsyncValue.data(null));

  void _invalidateMatchLists(int userId) {
    ref.invalidate(matchesProvider(userId));
    ref.invalidate(notificationCountsProvider(userId));
  }

  Future<void> submitOffer(
    int userId,
    int matchId,
    List<OfferItem> items,
  ) async {
    state = const AsyncValue.loading();
    try {
      final payload = OfferTradeRequest()
        ..userId = userId
        ..items.addAll(items);
      await client.post(
        '/api/v1/matches/$matchId/offer',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      _invalidateMatchLists(userId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateStatus(int userId, int matchId, String status) async {
    state = const AsyncValue.loading();
    try {
      final payload = UpdateMatchStatusRequest()
        ..status = status
        ..userId = userId;
      await client.post(
        '/api/v1/matches/$matchId/status',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      _invalidateMatchLists(userId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Apply completed-trade inventory for [userId] on [matchId].
  ///
  /// When [skipHaveDecrement] is false (default, #429), the giver's HAVE
  /// is decremented along with TRADE. When true, only TRADE is decremented
  /// (legacy opt-out).
  Future<void> applyInventory(
    int userId,
    int matchId, {
    bool skipHaveDecrement = false,
  }) async {
    state = const AsyncValue.loading();
    try {
      final payload = ApplyInventoryRequest()
        ..userId = userId
        ..skipHaveDecrement = skipHaveDecrement;
      await client.post(
        '/api/v1/matches/$matchId/apply-inventory',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      _invalidateMatchLists(userId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final matchControllerProvider =
    StateNotifierProvider<MatchController, AsyncValue<void>>((ref) {
      return MatchController(ref.watch(apiClientProvider), ref);
    });

// --- Chat ---

/// Messages for a match. Auto-disposes when no longer watched (e.g. chat
/// screen popped). Invalidated by [ChatController.sendMessage] and by the
/// screen's 3s poll timer.
final messagesProvider = FutureProvider.family.autoDispose<List<Message>, int>((
  ref,
  matchId,
) async {
  final client = ref.watch(apiClientProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  // #491: membership gate via caller user_id.
  final json = await client.get(
    '/api/v1/matches/$matchId/messages?user_id=${user.id}',
  );
  return (json as List).map((e) => Message()..mergeFromProto3Json(e)).toList();
});

/// Owns chat send mutation used by [ChatScreen].
///
/// #245: centralizes `SendMessageRequest` body construction (proto type),
/// `messagesProvider` invalidation, and loading/error state so the screen
/// can `ref.listen` instead of try/catch + SnackBar + invalidate at the
/// call site. Polling stays on the screen — see comment there.
class ChatController extends StateNotifier<AsyncValue<void>> {
  final ApiClient client;
  final Ref ref;

  ChatController(this.client, this.ref) : super(const AsyncValue.data(null));

  Future<void> sendMessage(int matchId, int senderId, String content) async {
    state = const AsyncValue.loading();
    try {
      final payload = SendMessageRequest()
        ..matchId = matchId
        ..senderId = senderId
        ..content = content;
      await client.post(
        '/api/v1/matches/$matchId/messages',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      ref.invalidate(messagesProvider(matchId));
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final chatControllerProvider =
    StateNotifierProvider<ChatController, AsyncValue<void>>((ref) {
      return ChatController(ref.watch(apiClientProvider), ref);
    });

// --- Search ---
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchProvider = FutureProvider<List<SearchResult>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return [];

  final client = ref.watch(apiClientProvider);
  final json = await client.get(
    '/api/v1/search?q=${Uri.encodeComponent(query.trim())}',
  );
  return (json as List)
      .map((e) => SearchResult()..mergeFromProto3Json(e))
      .toList();
});
