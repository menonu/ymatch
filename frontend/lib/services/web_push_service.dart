import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'web_push_platform.dart';
import 'web_push_platform_stub.dart'
    if (dart.library.html) 'web_push_platform_web.dart'
    as platform;

export 'web_push_platform.dart'
    show BrowserPushSubscription, decodeVapidPublicKey;

/// Orchestrates Web Push subscribe/unsubscribe against the ymatch API (#179).
class WebPushService {
  WebPushService({required ApiClient client, WebPushPlatform? platformImpl})
    : _client = client,
      _platform = platformImpl ?? platform.createWebPushPlatform();

  final ApiClient _client;
  final WebPushPlatform _platform;

  bool get isSupported => kIsWeb && _platform.isSupported;

  Future<String> permissionState() => _platform.permissionState();

  /// Fetch application-server VAPID public key, or null when push is disabled.
  Future<String?> fetchVapidPublicKey() async {
    try {
      final data = await _client.get('/api/v1/push/vapid-public-key');
      if (data is Map && data['publicKey'] is String) {
        final key = (data['publicKey'] as String).trim();
        return key.isEmpty ? null : key;
      }
      return null;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('404') || msg.contains('Not Found')) {
        return null;
      }
      rethrow;
    }
  }

  Future<BrowserPushSubscription?> currentSubscription() =>
      _platform.currentSubscription();

  /// Enable browser push for [userId]: permission → subscribe → persist.
  Future<BrowserPushSubscription> enable(int userId) async {
    final vapid = await fetchVapidPublicKey();
    if (vapid == null) {
      throw StateError('VAPID is not configured on the server');
    }
    await _platform.ensureServiceWorker();
    final sub = await _platform.subscribe(vapid);
    await _persist(userId, sub);
    return sub;
  }

  /// Drop browser subscription and delete backend row when possible.
  Future<void> disable(int userId) async {
    final existing = await _platform.currentSubscription();
    await _platform.unsubscribe();
    if (existing != null) {
      try {
        await _client.deleteJson('/api/v1/push/subscriptions?user_id=$userId', {
          'endpoint': existing.endpoint,
        });
      } catch (_) {
        // Best-effort: browser already unsubscribed.
      }
    }
  }

  /// If permission is already granted and a browser sub exists, re-PUT it.
  Future<bool> syncExisting(int userId) async {
    if (!isSupported) return false;
    final perm = await permissionState();
    if (perm != 'granted') return false;
    await _platform.ensureServiceWorker();
    final sub = await _platform.currentSubscription();
    if (sub == null) return false;
    await _persist(userId, sub);
    return true;
  }

  Future<void> _persist(int userId, BrowserPushSubscription sub) async {
    await _client.put('/api/v1/push/subscriptions?user_id=$userId', {
      'endpoint': sub.endpoint,
      'keys': {'p256dh': sub.p256dh, 'auth': sub.auth},
    });
  }
}
