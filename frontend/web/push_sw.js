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
  let data = {};

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
        data = payload;
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
      data: data,
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const targetPath = '/matches';

  event.waitUntil(
    (async () => {
      const allClients = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      });
      for (const client of allClients) {
        // Prefer focusing an existing app tab.
        if ('focus' in client) {
          try {
            const url = new URL(client.url);
            // Navigate if possible, otherwise focus.
            if ('navigate' in client) {
              await client.navigate(targetPath);
            }
            return client.focus();
          } catch (_) {
            return client.focus();
          }
        }
      }
      if (self.clients.openWindow) {
        return self.clients.openWindow(targetPath);
      }
    })(),
  );
});
