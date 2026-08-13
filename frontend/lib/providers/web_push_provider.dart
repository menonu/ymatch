import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/web_push_service.dart';
import 'auth_provider.dart';

/// Local preference: user wants match push enabled (#179).
///
/// Survives SPA reloads even if the browser PushSubscription is briefly
/// missing (e.g. after a service-worker race). Used to re-subscribe.
const kWebPushEnabledPrefKey = 'web_push_match_notifications_enabled';

/// UI-facing state for match push notifications (#179).
enum WebPushUiStatus {
  /// Still probing browser + server / auth.
  loading,

  /// Not web / no Push API / no service worker.
  unsupported,

  /// Server has no VAPID public key (push disabled).
  serverDisabled,

  /// Browser permission denied.
  denied,

  /// Supported but not subscribed (or user turned off).
  off,

  /// User wants push and browser subscription is active (or re-subscribed).
  on,

  /// Last enable/disable failed.
  error,
}

class WebPushState {
  const WebPushState({required this.status, this.message});

  final WebPushUiStatus status;
  final String? message;

  bool get isOn => status == WebPushUiStatus.on;
  bool get canToggle =>
      status == WebPushUiStatus.off ||
      status == WebPushUiStatus.on ||
      status == WebPushUiStatus.error;
}

final webPushServiceProvider = Provider<WebPushService>((ref) {
  return WebPushService(client: ref.watch(apiClientProvider));
});

class WebPushController extends StateNotifier<WebPushState> {
  WebPushController(this._ref, {bool autoRefresh = true})
    : super(const WebPushState(status: WebPushUiStatus.loading)) {
    if (autoRefresh) {
      // Re-sync when the signed-in user changes (switch account / logout).
      // Also re-run after auth hydrates from data(null) → guest/user.
      _ref.listen<AsyncValue<User?>>(authProvider, (prev, next) {
        if (next.isLoading) return;
        final prevId = prev?.valueOrNull?.id;
        final nextId = next.valueOrNull?.id;
        // Always refresh when auth settles or identity changes.
        if (prev == null || prev.isLoading || prevId != nextId) {
          refresh();
        }
      });
      refresh();
    }
  }

  final Ref _ref;

  /// Test helper to pin UI state without browser APIs.
  @visibleForTesting
  void debugSetState(WebPushState value) {
    state = value;
  }

  WebPushService get _service => _ref.read(webPushServiceProvider);

  Future<bool> _readEnabledPref() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kWebPushEnabledPrefKey) ?? false;
  }

  Future<void> _writeEnabledPref(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kWebPushEnabledPrefKey, enabled);
  }

  Future<void> refresh() async {
    state = const WebPushState(status: WebPushUiStatus.loading);
    try {
      if (!kIsWeb || !_service.isSupported) {
        state = const WebPushState(status: WebPushUiStatus.unsupported);
        return;
      }

      final vapid = await _service.fetchVapidPublicKey();
      if (vapid == null) {
        state = const WebPushState(status: WebPushUiStatus.serverDisabled);
        return;
      }

      final perm = await _service.permissionState();
      if (perm == 'denied') {
        state = const WebPushState(status: WebPushUiStatus.denied);
        return;
      }

      // AuthController starts as data(null) while checkLogin() is in flight.
      // Stay loading until auth has finished hydrating so we don't flash "off".
      final auth = _ref.read(authProvider);
      if (auth.isLoading) {
        state = const WebPushState(status: WebPushUiStatus.loading);
        return;
      }

      final user = auth.valueOrNull;
      if (user == null) {
        state = const WebPushState(status: WebPushUiStatus.off);
        return;
      }

      final wantsEnabled = await _readEnabledPref();
      final sub = await _service.currentSubscription();

      if (sub != null && perm == 'granted') {
        try {
          await _service.syncExisting(user.id);
          await _writeEnabledPref(true);
          state = const WebPushState(status: WebPushUiStatus.on);
          return;
        } catch (e) {
          state = WebPushState(
            status: WebPushUiStatus.error,
            message: e.toString(),
          );
          return;
        }
      }

      // Preference says enabled but browser sub is missing (e.g. Flutter SW
      // previously replaced push_sw.js). Re-subscribe automatically.
      if (wantsEnabled && perm == 'granted') {
        try {
          await _service.enable(user.id);
          state = const WebPushState(status: WebPushUiStatus.on);
          return;
        } catch (e) {
          state = WebPushState(
            status: WebPushUiStatus.error,
            message: e.toString(),
          );
          return;
        }
      }

      state = const WebPushState(status: WebPushUiStatus.off);
    } catch (e) {
      state = WebPushState(
        status: WebPushUiStatus.error,
        message: e.toString(),
      );
    }
  }

  Future<void> enable() async {
    final user = _ref.read(currentUserProvider);
    if (user == null) {
      state = const WebPushState(
        status: WebPushUiStatus.error,
        message: 'Not signed in',
      );
      return;
    }
    state = const WebPushState(status: WebPushUiStatus.loading);
    try {
      await _service.enable(user.id);
      await _writeEnabledPref(true);
      state = const WebPushState(status: WebPushUiStatus.on);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('permission') || msg.contains('not granted')) {
        state = const WebPushState(status: WebPushUiStatus.denied);
      } else if (msg.contains('VAPID')) {
        state = const WebPushState(status: WebPushUiStatus.serverDisabled);
      } else {
        state = WebPushState(status: WebPushUiStatus.error, message: msg);
      }
    }
  }

  Future<void> disable() async {
    final user = _ref.read(currentUserProvider);
    state = const WebPushState(status: WebPushUiStatus.loading);
    try {
      await _writeEnabledPref(false);
      if (user != null) {
        await _service.disable(user.id);
      } else {
        // Still drop browser subscription if possible.
        try {
          await _service.disable(0);
        } catch (_) {}
      }
      state = const WebPushState(status: WebPushUiStatus.off);
    } catch (e) {
      state = WebPushState(
        status: WebPushUiStatus.error,
        message: e.toString(),
      );
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      await enable();
    } else {
      await disable();
    }
  }
}

final webPushProvider = StateNotifierProvider<WebPushController, WebPushState>((
  ref,
) {
  return WebPushController(ref);
});
