import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../models/models.dart';
import 'auth_provider.dart';
import 'member_models.dart';

// --- Events ---
final eventsProvider = FutureProvider<List<Event>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final user = ref.watch(currentUserProvider);

  String url = '/api/v1/events';
  if (user != null) {
    url += '?user_id=${user.id}';
  }

  final json = await client.get(url);
  final events = (json as List)
      .map((e) => Event()..mergeFromProto3Json(e))
      .toList();

  // Sort favorites to the top
  events.sort((a, b) {
    if (a.hasIsFavorite() &&
        a.isFavorite &&
        (!b.hasIsFavorite() || !b.isFavorite))
      return -1;
    if ((!a.hasIsFavorite() || !a.isFavorite) &&
        b.hasIsFavorite() &&
        b.isFavorite)
      return 1;
    // Otherwise sort by id descending (newest first)
    return b.id.compareTo(a.id);
  });

  return events;
});

final favoriteGroupsProvider = FutureProvider<List<FavoriteGroup>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/user/${user.id}/favorite_groups');
  return (json as List)
      .map((e) => FavoriteGroup()..mergeFromProto3Json(e))
      .toList();
});

class EventsController extends StateNotifier<AsyncValue<void>> {
  final ApiClient client;
  EventsController(this.client) : super(const AsyncValue.data(null));

  Future<void> addEvent(String name, int creatorId, {String? status}) async {
    state = const AsyncValue.loading();
    try {
      final payload = CreateEventRequest()
        ..name = name
        ..creatorId = creatorId;
      if (status != null) payload.status = status;
      await client.post(
        '/api/v1/events',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // #266: rethrow so callers (dialogs) can surface a SnackBar instead of
      // closing as if the create succeeded.
      rethrow;
    }
  }

  Future<void> toggleFavorite(int eventId, int userId, bool isFavorite) async {
    // We don't necessarily need to set state to loading here if we do optimistic update,
    // but we can just fire and forget, then invalidate the provider.
    try {
      final payload = ToggleFavoriteRequest()
        ..userId = userId
        ..isFavorite = isFavorite;
      await client.post(
        '/api/v1/events/$eventId/favorite',
        payload.toProto3Json() as Map<String, dynamic>,
      );
    } catch (e) {
      // Don't rethrow: the caller (home_screen) relies on this returning
      // normally so it can ref.invalidate(eventsProvider) to refresh the
      // true state. At minimum log so the failure isn't silently lost (#239).
      debugPrint('toggleFavorite($eventId, $userId, $isFavorite) failed: $e');
    }
  }

  Future<void> toggleFavoriteGroup(
    int eventId,
    int userId,
    String groupName,
    bool isFavorite,
  ) async {
    try {
      final payload = ToggleFavoriteGroupRequest()
        ..userId = userId
        ..groupName = groupName
        ..isFavorite = isFavorite;
      await client.post(
        '/api/v1/events/$eventId/favorite_group',
        payload.toProto3Json() as Map<String, dynamic>,
      );
    } catch (e) {
      // See toggleFavorite: log, don't rethrow (#239).
      debugPrint(
        'toggleFavoriteGroup($eventId, $userId, $groupName, $isFavorite) '
        'failed: $e',
      );
    }
  }

  Future<void> registerView(int eventId, int userId) async {
    try {
      final payload = UserActionRequest()..userId = userId;
      await client.post(
        '/api/v1/events/$eventId/view',
        payload.toProto3Json() as Map<String, dynamic>,
      );
    } catch (e) {
      // Ignore errors for analytics
    }
  }

  Future<void> updateEvent(int eventId, int userId, String name) async {
    state = const AsyncValue.loading();
    try {
      final payload = UpdateEventRequest()
        ..userId = userId
        ..name = name;
      await client.put(
        '/api/v1/events/$eventId',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // #266: rethrow so the edit dialog can surface a failure SnackBar.
      rethrow;
    }
  }

  Future<void> deleteEventByCreator(int eventId, int userId) async {
    state = const AsyncValue.loading();
    try {
      await client.delete('/api/v1/admin/events/$eventId?user_id=$userId');
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // #266: rethrow so the delete confirm dialog can surface a failure SnackBar.
      rethrow;
    }
  }

  /// List event members via the public path (#442). Requires event.member.manage.
  Future<List<EventMemberInfo>> listEventMembers(
    int eventId,
    int userId,
  ) async {
    final json = await client.get(
      '/api/v1/events/$eventId/members?user_id=$userId',
    );
    final members = (json as Map<String, dynamic>)['members'] as List? ?? [];
    return members
        .map((e) => EventMemberInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Assign event editor via the public path (#442).
  Future<void> assignEventEditor(
    int eventId,
    int targetUserId,
    int userId,
  ) async {
    state = const AsyncValue.loading();
    try {
      await client.post(
        '/api/v1/events/$eventId/members/$targetUserId?user_id=$userId',
        {},
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Revoke event editor via the public path (#442). Never removes creator.
  Future<void> revokeEventEditor(
    int eventId,
    int targetUserId,
    int userId,
  ) async {
    state = const AsyncValue.loading();
    try {
      await client.delete(
        '/api/v1/events/$eventId/members/$targetUserId?user_id=$userId',
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Self-service event creator transfer (`PUT /events/:id/creator`, #442).
  Future<void> transferEventCreator(
    int eventId,
    int userId,
    int newCreatorId,
  ) async {
    state = const AsyncValue.loading();
    try {
      await client.put('/api/v1/events/$eventId/creator?user_id=$userId', {
        'newCreatorId': newCreatorId,
      });
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// List group members via the public path (#443). Requires group.member.manage.
  Future<List<GroupMemberInfo>> listGroupMembers(
    int eventId,
    String groupName,
    int userId,
  ) async {
    final encoded = Uri.encodeComponent(groupName);
    final json = await client.get(
      '/api/v1/events/$eventId/groups/$encoded/members?user_id=$userId',
    );
    final members = (json as Map<String, dynamic>)['members'] as List? ?? [];
    return members
        .map((e) => GroupMemberInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Assign group editor via the public path (#443).
  Future<void> assignGroupEditor(
    int eventId,
    String groupName,
    int targetUserId,
    int userId,
  ) async {
    state = const AsyncValue.loading();
    try {
      final encoded = Uri.encodeComponent(groupName);
      await client.post(
        '/api/v1/events/$eventId/groups/$encoded/members/$targetUserId?user_id=$userId',
        {},
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Revoke group editor via the public path (#443). Never removes creator.
  Future<void> revokeGroupEditor(
    int eventId,
    String groupName,
    int targetUserId,
    int userId,
  ) async {
    state = const AsyncValue.loading();
    try {
      final encoded = Uri.encodeComponent(groupName);
      await client.delete(
        '/api/v1/events/$eventId/groups/$encoded/members/$targetUserId?user_id=$userId',
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Self-service group creator transfer
  /// (`PUT /events/:id/groups/:name/creator`, #443).
  Future<void> transferGroupCreator(
    int eventId,
    String groupName,
    int userId,
    int newCreatorId,
  ) async {
    state = const AsyncValue.loading();
    try {
      final encoded = Uri.encodeComponent(groupName);
      await client.put(
        '/api/v1/events/$eventId/groups/$encoded/creator?user_id=$userId',
        {'newCreatorId': newCreatorId},
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> generateDebugData(int creatorId) async {
    state = const AsyncValue.loading();
    try {
      // 1. Create a debug event
      final eventPayload = CreateEventRequest()
        ..name =
            'Debug Event ${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}'
        ..creatorId = creatorId;
      final eventJson = await client.post(
        '/api/v1/events',
        eventPayload.toProto3Json() as Map<String, dynamic>,
      );
      final event = Event()..mergeFromProto3Json(eventJson);

      // 2. Generate 50 items in parallel across 5 groups (10 items each)
      final futures = <Future>[];
      final groups = [
        'Photo Cards',
        'Badges',
        'Acrylic Stands',
        'Posters',
        'T-Shirts',
      ];

      for (int g = 0; g < groups.length; g++) {
        for (int i = 1; i <= 10; i++) {
          final globalIndex = (g * 10) + i;
          final hasIcon = (globalIndex % 4 != 0); // Every 4th item has no icon
          final photoUrl = hasIcon
              ? 'https://picsum.photos/seed/${event.id}_$globalIndex/200'
              : '';

          final merchPayload = CreateMerchRequest()
            ..name = '${groups[g]} #$i'
            ..photoUrl = photoUrl
            ..groupName = groups[g];
          futures.add(
            client.post(
              '/api/v1/events/${event.id}/merch',
              merchPayload.toProto3Json() as Map<String, dynamic>,
            ),
          );
        }
      }
      await Future.wait(futures);

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // #266: rethrow so the debug tab does not show a success SnackBar on failure.
      rethrow;
    }
  }
}

final eventsControllerProvider =
    StateNotifierProvider<EventsController, AsyncValue<void>>((ref) {
      return EventsController(ref.watch(apiClientProvider));
    });
