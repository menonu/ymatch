import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/api_client.dart';
import '../models/models.dart';

// --- Auth / Current User ---
class AuthController extends StateNotifier<AsyncValue<User?>> {
  final ApiClient client;

  AuthController(this.client) : super(const AsyncValue.data(null)) {
    checkLogin();
  }

  Future<void> checkLogin() async {
    final prefs = await SharedPreferences.getInstance();
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
      final user = User.fromJson(json);
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
      final user = User.fromJson(json);
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
      final user = User.fromJson(json);
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
final eventsProvider = FutureProvider<List<EventGroup>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/events');
  return (json as List).map((e) => EventGroup.fromJson(e)).toList();
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
}

final eventsControllerProvider = StateNotifierProvider<EventsController, AsyncValue<void>>((ref) {
  return EventsController(ref.watch(apiClientProvider));
});

// --- Merchandise (Family provider by event_id) ---
final merchProvider = FutureProvider.family<List<Merchandise>, int>((ref, eventId) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/events/$eventId/merch');
  return (json as List).map((e) => Merchandise.fromJson(e)).toList();
});

class MerchController extends StateNotifier<AsyncValue<void>> {
  final ApiClient client;
  MerchController(this.client) : super(const AsyncValue.data(null));

  Future<void> addMerch(int eventId, String name, String photoUrl) async {
    state = const AsyncValue.loading();
    try {
      await client.post('/api/v1/events/$eventId/merch', {
        'event_id': eventId,
        'name': name,
        'photo_url': photoUrl,
      });
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
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
    return (json as List).map((e) => InventoryItem.fromJson(e)).toList();
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
          return item.copyWith(quantity: quantity);
        }
        return item;
      }).toList();

      if (!found && quantity > 0) {
        newList.add(InventoryItem(
          id: 0,
          userId: userId,
          merchId: merchId,
          status: status,
          quantity: quantity,
          merchName: '',
        ));
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
    } catch (e, st) {
      state = previousState;
    }
  }
}

final inventoryProvider = AsyncNotifierProviderFamily<UserInventoryNotifier, List<InventoryItem>, int>(() {
  return UserInventoryNotifier();
});
