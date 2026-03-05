import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/api_client.dart';
import '../models/models.dart';

// --- System ---
final backendSystemStatusProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.watch(apiClientProvider);
  try {
    final response = await client.get('/api/v1/system/status');
    return response as Map<String, dynamic>;
  } catch (e) {
    return {'backend_version': 'error', 'resources': null};
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
      final json = await client.post('/api/v1/auth/guest', {
        'uuid': uuid,
      });
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
      final json = await client.post('/api/v1/auth/login', {
        'username': username,
        'password': password,
      });
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
      final json = await client.post('/api/v1/auth/signup', {
         'username': username,
         'password': password,
         'device_token': 'web-v1',
      });
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
}

final authProvider = StateNotifierProvider<AuthController, AsyncValue<User?>>((ref) {
  return AuthController(ref.watch(apiClientProvider));
});

final currentUserProvider = Provider<User?>((ref) {
   return ref.watch(authProvider).value;
});

// --- Events ---
final eventsProvider = FutureProvider<List<Event>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final user = ref.watch(currentUserProvider);
  
  String url = '/api/v1/events';
  if (user != null) {
    url += '?user_id=${user.id}';
  }
  
  final json = await client.get(url);
  final events = (json as List).map((e) => Event()..mergeFromProto3Json(e)).toList();
  
  // Sort favorites to the top
  events.sort((a, b) {
    if (a.hasIsFavorite() && a.isFavorite && (!b.hasIsFavorite() || !b.isFavorite)) return -1;
    if ((!a.hasIsFavorite() || !a.isFavorite) && b.hasIsFavorite() && b.isFavorite) return 1;
    // Otherwise sort by id descending (newest first)
    return b.id.compareTo(a.id);
  });
  
  return events;
});

class EventsController extends StateNotifier<AsyncValue<void>> {
  final ApiClient client;
  EventsController(this.client) : super(const AsyncValue.data(null));

  Future<void> addEvent(String name, int creatorId) async {
    state = const AsyncValue.loading();
    try {
      await client.post('/api/v1/events', {
        'name': name,
        'creator_id': creatorId,
      });
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> toggleFavorite(int eventId, int userId, bool isFavorite) async {
    // We don't necessarily need to set state to loading here if we do optimistic update,
    // but we can just fire and forget, then invalidate the provider.
    try {
      await client.post('/api/v1/events/$eventId/favorite', {
        'user_id': userId,
        'is_favorite': isFavorite,
      });
    } catch (e) {
      // Handle error if needed
    }
  }

  Future<void> registerView(int eventId, int userId) async {
    try {
      await client.post('/api/v1/events/$eventId/view', {
        'user_id': userId,
      });
    } catch (e) {
      // Ignore errors for analytics
    }
  }

  Future<void> generateDebugData(int creatorId) async {
    state = const AsyncValue.loading();
    try {
      // 1. Create a debug event
      final eventJson = await client.post('/api/v1/events', {
        'name': 'Debug Event ${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
        'creator_id': creatorId,
      });
      final event = Event()..mergeFromProto3Json(eventJson);

      // 2. Generate 50 items in parallel across 5 groups (10 items each)
      final futures = <Future>[];
      final groups = ['Photo Cards', 'Badges', 'Acrylic Stands', 'Posters', 'T-Shirts'];
      
      for (int g = 0; g < groups.length; g++) {
        for (int i = 1; i <= 10; i++) {
          final globalIndex = (g * 10) + i;
          final hasIcon = (globalIndex % 4 != 0); // Every 4th item has no icon
          final photoUrl = hasIcon ? 'https://picsum.photos/seed/${event.id}_$globalIndex/200' : '';
          
          futures.add(
            client.post('/api/v1/events/${event.id}/merch', {
              'event_id': event.id,
              'name': '${groups[g]} #$i',
              'photo_url': photoUrl,
              'group_name': groups[g],
            })
          );
        }
      }
      await Future.wait(futures);

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final eventsControllerProvider = StateNotifierProvider<EventsController, AsyncValue<void>>((ref) {
  return EventsController(ref.watch(apiClientProvider));
});

// --- Merchandise (Family provider by event_id) ---
final merchProvider = FutureProvider.family<List<Merchandise>, int>((ref, eventId) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/events/$eventId/merch');
  return (json as List).map((e) => Merchandise()..mergeFromProto3Json(e)).toList();
});

class MerchController extends StateNotifier<AsyncValue<void>> {
  final ApiClient client;
  MerchController(this.client) : super(const AsyncValue.data(null));

  Future<void> addMerch(int eventId, String name, String photoUrl, [String? groupName]) async {
    state = const AsyncValue.loading();
    try {
      final payload = {
        'event_id': eventId,
        'name': name,
        'photo_url': photoUrl,
      };
      if (groupName != null && groupName.isNotEmpty) {
        payload['group_name'] = groupName;
      }
      
      await client.post('/api/v1/events/$eventId/merch', payload);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateSortOrder(int eventId, Map<int, int> sortOrders) async {
    try {
      await client.post('/api/v1/events/$eventId/merch/sort', {
        'event_id': eventId,
        'sort_orders': sortOrders.map((k, v) => MapEntry(k.toString(), v)), // JSON keys must be strings
      });
    } catch (e) {
      // Ignore errors for optimistic UI or show a toast
    }
  }
}

final merchControllerProvider = StateNotifierProvider<MerchController, AsyncValue<void>>((ref) {
  return MerchController(ref.watch(apiClientProvider));
});

// --- Inventory ---
// --- Inventory Notifier (Optimistic Updates) ---
class UserInventoryNotifier extends FamilyAsyncNotifier<List<InventoryItem>, int> {
  @override
  Future<List<InventoryItem>> build(int arg) async {
    final client = ref.watch(apiClientProvider);
    final json = await client.get('/api/v1/user/$arg/inventory');
    return (json as List).map((e) => InventoryItem()..mergeFromProto3Json(e)).toList();
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
        newList.add(InventoryItem()
          ..id = 0
          ..userId = userId
          ..merchId = merchId
          ..status = status
          ..quantity = quantity
          ..merchName = '');
      }
      // filter out 0 quantity if desired, but for now just keep
      state = AsyncValue.data(newList);
    }

    // 2. Network Call
    try {
      final client = ref.read(apiClientProvider);
      await client.post('/api/v1/user/inventory', {
        'user_id': userId,
        'merch_id': merchId,
        'status': status,
        'quantity': quantity,
      });
      // Do NOT invalidate yet, let the user keep clicking.
      // We can refresh later or on some other event if needed.
    } catch (e) {
      state = previousState;
    }
  }
}

final inventoryProvider = AsyncNotifierProviderFamily<UserInventoryNotifier, List<InventoryItem>, int>(() {
  return UserInventoryNotifier();
});

// --- Admin ---
final adminMerchProvider = FutureProvider<List<Merchandise>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/admin/merch');
  return (json as List).map((e) => Merchandise()..mergeFromProto3Json(e)).toList();
});

final adminMatchesProvider = FutureProvider<List<TradeMatch>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/admin/matches');
  return (json as List).map((e) => TradeMatch()..mergeFromProto3Json(e)).toList();
});
