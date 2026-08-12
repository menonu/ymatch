// Web Push service worker for ymatch (#179 / ADR 0015).
// Registered separately from Flutter's caching service worker.
// Handles background push display and notification clicks.

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', (event) => {
  let title = 'New match';
  let body = 'You have a new match! Check it out in the Trades tab.';
  let data = { path: '/matches' };

  try {
    if (event.data) {
      const payload = event.data.json();
      if (payload && typeof payload === 'object') {
        if (typeof payload.title === 'string' && payload.title) {
          title = payload.title;
        }
        if (typeof payload.body === 'string' && payload.body) {
          body = payload.body;
        }
        data = Object.assign({ path: '/matches' }, payload);
      }
    }
  } catch (_) {
    try {
      const text = event.data && event.data.text();
      if (text) body = text;
    } catch (_) {
      // keep defaults
    }
  }

  event.waitUntil(
    self.registration.showNotification(title, {
      body: body,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      // Required on some platforms so the click is associated with our origin.
      data: data,
    }),
  );
});

/**
 * Open / focus the app on notification click.
 *
 * Important: clients.openWindow requires an absolute http(s) URL. Relative
 * paths like "/matches" are ignored or no-op in several browsers (including
 * Chromium desktop), which matches "tap does nothing / browser never opens".
 */
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const path =
    (event.notification.data && event.notification.data.path) || '/matches';
  // Absolute URL rooted at the service worker's origin (e.g. https://host/matches).
  const targetUrl = new URL(
    path.startsWith('/') ? path : `/${path}`,
    self.location.origin,
  ).href;

  event.waitUntil(openOrFocusApp(targetUrl));
});

async function openOrFocusApp(targetUrl) {
  const allClients = await self.clients.matchAll({
    type: 'window',
    includeUncontrolled: true,
  });

  // Prefer an existing same-origin tab/window.
  for (const client of allClients) {
    if (!client.url || !client.url.startsWith(self.location.origin)) {
      continue;
    }
    try {
      // Focus first (user gesture already consumed by the click).
      if ('focus' in client) {
        await client.focus();
      }
      // Best-effort SPA navigation without full reload.
      if ('navigate' in client) {
        try {
          await client.navigate(targetUrl);
        } catch (_) {
          // Some browsers disallow navigate; fall through to postMessage.
        }
      }
      try {
        client.postMessage({
          type: 'ymatch-notification-click',
          url: targetUrl,
          path: new URL(targetUrl).pathname,
        });
      } catch (_) {
        // postMessage optional
      }
      return client;
    } catch (_) {
      // try next client
    }
  }

  // No usable client: must open a new window with an absolute URL.
  if (self.clients.openWindow) {
    return self.clients.openWindow(targetUrl);
  }
  return undefined;
}
