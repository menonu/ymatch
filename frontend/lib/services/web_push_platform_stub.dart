import 'web_push_platform.dart';

/// Non-web / test default: Web Push is unsupported.
class StubWebPushPlatform implements WebPushPlatform {
  @override
  bool get isSupported => false;

  @override
  Future<String> permissionState() async => 'unsupported';

  @override
  Future<void> ensureServiceWorker() async {}

  @override
  Future<BrowserPushSubscription?> currentSubscription() async => null;

  @override
  Future<BrowserPushSubscription> subscribe(String vapidPublicKey) {
    throw UnsupportedError('Web Push is not available on this platform');
  }

  @override
  Future<void> unsubscribe() async {}
}

WebPushPlatform createWebPushPlatform() => StubWebPushPlatform();
