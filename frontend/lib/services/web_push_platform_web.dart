// Web-only implementation of [WebPushPlatform] using package:web (#179).

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_push_platform.dart';

const _swPath = 'push_sw.js';

class BrowserWebPushPlatform implements WebPushPlatform {
  web.ServiceWorkerRegistration? _registration;

  @override
  bool get isSupported {
    try {
      // Accessing serviceWorker throws if unsupported in some browsers.
      // ignore: unnecessary_null_comparison
      return web.window.navigator.serviceWorker != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> permissionState() async {
    if (!isSupported) return 'unsupported';
    final n = web.Notification.permission;
    if (n == 'granted' || n == 'denied' || n == 'default') return n;
    return 'default';
  }

  @override
  Future<void> ensureServiceWorker() async {
    final container = web.window.navigator.serviceWorker;
    _registration = await container.register(_swPath.toJS).toDart;
    await container.ready.toDart;
    final existing = await container.getRegistration().toDart;
    _registration ??= existing;
  }

  Future<web.ServiceWorkerRegistration> _readyRegistration() async {
    if (_registration != null) return _registration!;
    await ensureServiceWorker();
    final reg = _registration;
    if (reg == null) {
      throw StateError('Service worker registration failed');
    }
    return reg;
  }

  @override
  Future<BrowserPushSubscription?> currentSubscription() async {
    if (!isSupported) return null;
    final reg = await _readyRegistration();
    final sub = await reg.pushManager.getSubscription().toDart;
    if (sub == null) return null;
    return _fromSubscription(sub);
  }

  @override
  Future<BrowserPushSubscription> subscribe(String vapidPublicKey) async {
    if (!isSupported) {
      throw UnsupportedError('Web Push is not supported in this browser');
    }
    if (web.Notification.permission != 'granted') {
      final result = (await web.Notification.requestPermission().toDart).toDart;
      if (result != 'granted') {
        throw StateError('Notification permission not granted');
      }
    }

    final reg = await _readyRegistration();
    final keyBytes = Uint8List.fromList(decodeVapidPublicKey(vapidPublicKey));
    final options = web.PushSubscriptionOptionsInit(
      userVisibleOnly: true,
      applicationServerKey: keyBytes.toJS,
    );
    final sub = await reg.pushManager.subscribe(options).toDart;
    return _fromSubscription(sub);
  }

  @override
  Future<void> unsubscribe() async {
    if (!isSupported) return;
    final reg = await _readyRegistration();
    final sub = await reg.pushManager.getSubscription().toDart;
    if (sub != null) {
      await sub.unsubscribe().toDart;
    }
  }

  BrowserPushSubscription _fromSubscription(web.PushSubscription sub) {
    final json = sub.toJSON();
    final endpoint = json.endpoint;
    final keys = json.keys;
    final p256dh = keys.getProperty('p256dh'.toJS);
    final auth = keys.getProperty('auth'.toJS);
    final p256dhStr = p256dh != null && p256dh.isA<JSString>()
        ? (p256dh as JSString).toDart
        : p256dh?.dartify()?.toString() ?? '';
    final authStr = auth != null && auth.isA<JSString>()
        ? (auth as JSString).toDart
        : auth?.dartify()?.toString() ?? '';

    if (endpoint.isEmpty || p256dhStr.isEmpty || authStr.isEmpty) {
      // Fallback via getKey ArrayBuffers.
      final pKey = sub.getKey('p256dh');
      final aKey = sub.getKey('auth');
      final pB64 = _bufferToBase64Url(pKey);
      final aB64 = _bufferToBase64Url(aKey);
      if (sub.endpoint.isEmpty || pB64.isEmpty || aB64.isEmpty) {
        throw StateError('Incomplete PushSubscription from browser');
      }
      return BrowserPushSubscription(
        endpoint: sub.endpoint,
        p256dh: pB64,
        auth: aB64,
      );
    }

    return BrowserPushSubscription(
      endpoint: endpoint,
      p256dh: p256dhStr,
      auth: authStr,
    );
  }

  String _bufferToBase64Url(JSArrayBuffer? buffer) {
    if (buffer == null) return '';
    final dartBuf = buffer.toDart;
    final bytes = dartBuf.asUint8List();
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

WebPushPlatform createWebPushPlatform() => BrowserWebPushPlatform();
