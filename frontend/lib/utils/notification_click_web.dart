// Web-only: open Matches when a push notification is clicked (#179).
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:web/web.dart' as web;

/// Listen for service-worker `postMessage` from `push_sw.js` notificationclick.
///
/// When an existing tab is focused, the SW may post this message so Flutter
/// GoRouter can navigate without a full page reload.
void installNotificationClickHandler(GoRouter router) {
  if (!kIsWeb) return;

  web.window.addEventListener(
    'message',
    (web.Event event) {
      try {
        final me = event as web.MessageEvent;
        final data = me.data.dartify();
        if (data is! Map) return;
        if (data['type'] != 'ymatch-notification-click') return;
        final path = data['path']?.toString();
        if (path == null || path.isEmpty) return;
        // Only allow in-app paths.
        if (!path.startsWith('/')) return;
        router.go(path);
      } catch (_) {
        // Ignore malformed messages.
      }
    }.toJS,
  );
}
