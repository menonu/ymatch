import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/api_client.dart';
import '../models/models.dart';

// --- Auth / Current User ---

/// Whether debug-only guest-session overrides are enabled.
///
/// Defaults to [kDebugMode]: production/release builds never honor `dev_user`
/// URL params and never surface the Admin Debug tab (#499). Tests may flip
/// this for release-path coverage; always restore in tearDown.
bool enableDevSessionOverrides = kDebugMode;

/// URI used when resolving `dev_user` overrides. Defaults to [Uri.base];
/// tests may override to inject query/fragment params.
@visibleForTesting
Uri Function() currentAppUri = () => Uri.base;

/// Parse a non-empty `dev_user` value from [uri] query or hash fragment.
///
/// Supports both `?dev_user=...` and hash-based routes (`#/?dev_user=...`).
@visibleForTesting
String? parseDevUserFromUri(Uri uri) {
  final fromQuery = uri.queryParameters['dev_user'];
  if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;

  final fragment = uri.fragment;
  if (!fragment.contains('dev_user=')) return null;
  try {
    // Hash routes look like `/#/?dev_user=uuid` or `/?dev_user=uuid`.
    final fragmentUri = Uri.parse(fragment.replaceFirst(RegExp(r'^/+'), ''));
    final fromFragment = fragmentUri.queryParameters['dev_user'];
    if (fromFragment != null && fromFragment.isNotEmpty) return fromFragment;
  } catch (_) {
    // Non-web / malformed fragment — ignore.
  }
  return null;
}

class AuthController extends StateNotifier<AsyncValue<User?>> {
  final ApiClient client;

  AuthController(this.client) : super(const AsyncValue.data(null)) {
    checkLogin();
  }

  Future<void> checkLogin() async {
    final prefs = await SharedPreferences.getInstance();

    // Debug-only: multi-tab testing via `?dev_user=` / hash `dev_user=`.
    // Production builds must never auto-login from shareable URL params (#499).
    if (enableDevSessionOverrides) {
      try {
        final devUser = parseDevUserFromUri(currentAppUri());
        if (devUser != null) {
          // Do NOT persist to SharedPreferences — each tab keeps its own session.
          await guestLogin(devUser);
          return;
        }
      } catch (_) {
        // Fallback for non-web environments if necessary
      }
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
