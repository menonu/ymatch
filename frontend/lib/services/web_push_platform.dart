import 'dart:convert';

/// Browser PushSubscription fields we persist to the backend (#179).
class BrowserPushSubscription {
  const BrowserPushSubscription({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });

  final String endpoint;
  final String p256dh;
  final String auth;
}

/// Platform bridge for Web Push (service worker + Push API).
///
/// Created via [createWebPushPlatform] (stub on IO, browser on web).
abstract class WebPushPlatform {
  /// True when the runtime can register a service worker and use PushManager.
  bool get isSupported;

  /// `default` | `granted` | `denied` | `unsupported`
  Future<String> permissionState();

  /// Ensure the push service worker is registered and ready.
  Future<void> ensureServiceWorker();

  /// Current browser subscription, if any.
  Future<BrowserPushSubscription?> currentSubscription();

  /// Subscribe with the application-server VAPID public key (URL-safe base64).
  Future<BrowserPushSubscription> subscribe(String vapidPublicKey);

  /// Unsubscribe the current browser subscription (no-op if none).
  Future<void> unsubscribe();
}

/// Decode a URL-safe base64 (no padding) VAPID public key to raw bytes.
///
/// Pure helper — unit-tested without a browser.
List<int> decodeVapidPublicKey(String base64Url) {
  var normalized = base64Url.trim().replaceAll('-', '+').replaceAll('_', '/');
  final mod = normalized.length % 4;
  if (mod > 0) {
    normalized = normalized.padRight(normalized.length + (4 - mod), '=');
  }
  return base64Decode(normalized);
}
