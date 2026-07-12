import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/api_client.dart';
import '../models/models.dart';

// --- System ---
final backendSystemStatusProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  final client = ref.watch(apiClientProvider);
  try {
    final response = await client.get('/api/v1/system/status');
    return response as Map<String, dynamic>;
  } catch (e) {
    return {'backend_version': 'error', 'resources': null};
  }
});

// Checks if backend is reachable. Can be invalidated to recheck.
final backendHealthProvider = FutureProvider.autoDispose<bool>((ref) async {
  final client = ref.watch(apiClientProvider);
  try {
    await client.get('/api/v1/events');
    return true;
  } on BackendUnavailableException {
    return false;
  } catch (_) {
    // Other errors (e.g. 401) still mean backend is reachable
    return true;
  }
});

// --- Auth / Current User ---
class AuthController extends StateNotifier<AsyncValue<User?>> {
  final ApiClient client;

  AuthController(this.client) : super(const AsyncValue.data(null)) {
    checkLogin();
  }

  Future<void> checkLogin() async {
    final prefs = await SharedPreferences.getInstance();

    // Support dev_user URL parameter for easier testing (multi-tab support)
    String? devUser;
    try {
      // Try to find dev_user in query parameters (handling both normal and hash-based URLs)
      devUser = Uri.base.queryParameters['dev_user'];
      if (devUser == null && Uri.base.fragment.contains('dev_user=')) {
        final fragmentUri = Uri.parse(Uri.base.fragment.replaceFirst('/', ''));
        devUser = fragmentUri.queryParameters['dev_user'];
      }
    } catch (_) {
      // Fallback for non-web environments if necessary
    }

    if (devUser != null && devUser.isNotEmpty) {
      // Do NOT persist dev_user to SharedPreferences - each tab uses its own dev session
      await guestLogin(devUser);
      return;
    }

    // Normal flow: check for saved UUID
    final String? uuid = prefs.getString('user_uuid');
    if (uuid != null) {
      await guestLogin(uuid);
    }
    // Else: stay in initial state (null), showing Welcome Screen.
  }

  Future<void> startGuestSession() async {
    final prefs = await SharedPreferences.getInstance();
    final newUuid = const Uuid().v4();
    await prefs.setString('user_uuid', newUuid);
    await guestLogin(newUuid);
  }

  Future<void> guestLogin(String uuid) async {
    state = const AsyncValue.loading();
    try {
      // Use a mock device token for the guest session.
      // In a real app, this would come from a push notification plugin.
      final mockDeviceToken = 'mock-token-${uuid.substring(0, 8)}';

      final payload = GuestLoginRequest()
        ..uuid = uuid
        ..deviceToken = mockDeviceToken;
      final json = await client.post(
        '/api/v1/auth/guest',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      final user = User()..mergeFromProto3Json(json);
      state = AsyncValue.data(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> restoreAccount(String uuid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_uuid', uuid);
    await guestLogin(uuid);
  }

  // Keep legacy login for admin/debug if needed, but not primary
  Future<void> login(String username, String password) async {
    state = const AsyncValue.loading();
    try {
      final payload = LoginRequest()
        ..username = username
        ..password = password;
      final json = await client.post(
        '/api/v1/auth/login',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      final user = User()..mergeFromProto3Json(json);
      // Also save UUID if this user has one? For now just session.
      state = AsyncValue.data(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> signup(String username, String password) async {
    // ... legacy signup ...
    state = const AsyncValue.loading();
    try {
      final payload = CreateUserRequest()
        ..username = username
        ..password = password
        ..deviceToken = 'web-v1';
      final json = await client.post(
        '/api/v1/auth/signup',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      final user = User()..mergeFromProto3Json(json);
      state = AsyncValue.data(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void logout() async {
    // For guest system, logout might just mean clearing local state,
    // but usually we want to stay logged in.
    // If "Switch Account", clear prefs.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_uuid');
    state = const AsyncValue.data(null);
  }

  Future<void> updateUsername(int userId, String newUsername) async {
    final payload = UpdateUsernameRequest()
      ..userId = userId
      ..username = newUsername;
    final data = await client.put(
      '/api/v1/users/$userId',
      payload.toProto3Json() as Map<String, dynamic>,
    );
    final user = User()..mergeFromProto3Json(data);
    state = AsyncValue.data(user);
  }
}

final authProvider = StateNotifierProvider<AuthController, AsyncValue<User?>>((
  ref,
) {
  return AuthController(ref.watch(apiClientProvider));
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authProvider).value;
});

// --- How-to hint (first-login emphasis, #336) ---
// Persists whether the user has already seen / opened the How to Trade guide
// via the AppBar help icon, so the icon can be emphasized only on the first
// login after which it becomes a plain icon. Stored locally in
// SharedPreferences ("how_to_hint_seen") — no backend state involved.
class HowToHintSeenController extends StateNotifier<bool> {
  // Default to "seen" (plain icon) until the persisted value has loaded, so a
  // returning user who already opened the guide does not see a one-frame
  // first-login emphasis flash before _load() resolves. A genuinely-new user
  // flips to "not seen" (emphasized) once the persisted value is read.
  HowToHintSeenController() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('how_to_hint_seen') ?? false;
  }

  Future<void> markSeen() async {
    if (state) return;
    state = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('how_to_hint_seen', true);
  }
}

final howToHintSeenProvider =
    StateNotifierProvider<HowToHintSeenController, bool>(
      (ref) => HowToHintSeenController(),
    );

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

// --- My event role (#366) ---
// The caller's effective standing on a single event, used to gate the Add Merch
// button without reading the denormalized `User.role`. `canCreateMerch` is the
// exact `merch.create` decision the backend enforces, so the gate is not a
// client-side re-derivation. Returns `null` when there is no logged-in user or
// the fetch fails — both leave the button hidden (the safe default; the
// backend 403 remains the defense-in-depth backstop on tap).
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

class MerchController extends StateNotifier<AsyncValue<void>> {
  final ApiClient client;
  MerchController(this.client) : super(const AsyncValue.data(null));

  Future<void> addMerch(
    int eventId,
    String name,
    String photoUrl, [
    String? groupName,
    int? creatorId,
    String? status,
  ]) async {
    state = const AsyncValue.loading();
    try {
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
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // #227: rethrow so the caller can show a real error message.
      // Without this, the add_merch_screen shows a misleading
      // "Added successfully" SnackBar on 422.
      rethrow;
    }
  }

  Future<void> updateMerch(
    int eventId,
    int merchId,
    int userId, {
    String? name,
    String? photoUrl,
    String? groupName,
  }) async {
    state = const AsyncValue.loading();
    try {
      final payload = UpdateMerchRequest()..userId = userId;
      if (name != null) payload.name = name;
      if (photoUrl != null) payload.photoUrl = photoUrl;
      if (groupName != null) payload.groupName = groupName;
      await client.put(
        '/api/v1/events/$eventId/merch/$merchId',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // #299: rethrow so the caller (e.g. the edit-name dialog) can surface
      // the backend error (such as a duplicate-name 400) instead of
      // silently swallowing it and closing the dialog as if it succeeded.
      rethrow;
    }
  }

  Future<void> deleteMerchByCreator(
    int eventId,
    int merchId,
    int userId,
  ) async {
    state = const AsyncValue.loading();
    try {
      await client.delete(
        '/api/v1/events/$eventId/merch/$merchId?user_id=$userId',
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      // #266: rethrow so the delete dialog can surface a failure SnackBar.
      rethrow;
    }
  }
}

final merchControllerProvider =
    StateNotifierProvider<MerchController, AsyncValue<void>>((ref) {
      return MerchController(ref.watch(apiClientProvider));
    });

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
          return InventoryItem()
            ..id = item.id
            ..userId = item.userId
            ..merchId = item.merchId
            ..status = item.status
            ..quantity = quantity
            ..merchName = item.merchName;
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

// --- Admin ---
class AdminGroup {
  const AdminGroup({
    required this.eventId,
    required this.eventName,
    required this.groupName,
    required this.itemCount,
  });

  final int eventId;
  final String eventName;
  final String groupName;
  final int itemCount;

  factory AdminGroup.fromJson(Map<String, dynamic> json) => AdminGroup(
    eventId: json['eventId'] as int,
    eventName: json['eventName'] as String,
    groupName: json['groupName'] as String,
    itemCount: json['itemCount'] as int,
  );
}

final adminGroupsProvider = FutureProvider<List<AdminGroup>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/admin/groups');
  return (json as List)
      .map((e) => AdminGroup.fromJson(e as Map<String, dynamic>))
      .toList();
});

final adminMerchProvider = FutureProvider<List<Merchandise>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/admin/merch');
  return (json as List)
      .map((e) => Merchandise()..mergeFromProto3Json(e))
      .toList();
});

final adminMatchesProvider = FutureProvider<List<TradeMatch>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/admin/matches');
  return (json as List)
      .map((e) => TradeMatch()..mergeFromProto3Json(e))
      .toList();
});

// --- Admin Users ---
final adminUsersProvider = FutureProvider<List<User>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/users');
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
    }
  }

  Future<void> deleteEvent(int eventId, int userId) async {
    state = const AsyncValue.loading();
    try {
      await client.delete('/api/v1/admin/events/$eventId?user_id=$userId');
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteMerch(int merchId, int userId) async {
    state = const AsyncValue.loading();
    try {
      await client.delete('/api/v1/admin/merch/$merchId?user_id=$userId');
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteMatch(int matchId, int userId) async {
    state = const AsyncValue.loading();
    try {
      await client.delete('/api/v1/admin/matches/$matchId?user_id=$userId');
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
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
