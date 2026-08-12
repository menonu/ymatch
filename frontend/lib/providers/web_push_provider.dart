import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/web_push_service.dart';
import 'auth_provider.dart';

/// UI-facing state for match push notifications (#179).
enum WebPushUiStatus {
  /// Still probing browser + server.
  loading,

  /// Not web / no Push API / no service worker.
  unsupported,

  /// Server has no VAPID public key (push disabled).
  serverDisabled,

  /// Browser permission denied.
  denied,

  /// Supported but not subscribed (or permission not granted yet).
  off,

  /// Browser subscription present and persisted for the current user.
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
      _ref.listen<User?>(currentUserProvider, (prev, next) {
        final prevId = prev?.id;
        final nextId = next?.id;
        if (prevId != nextId) {
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

      final user = _ref.read(currentUserProvider);
      if (user == null) {
        state = const WebPushState(status: WebPushUiStatus.off);
        return;
      }

      if (perm == 'granted') {
        final sub = await _service.currentSubscription();
        if (sub != null) {
          try {
            await _service.syncExisting(user.id);
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
    if (user == null) {
      state = const WebPushState(status: WebPushUiStatus.off);
      return;
    }
    state = const WebPushState(status: WebPushUiStatus.loading);
    try {
      await _service.disable(user.id);
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
