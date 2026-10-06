// Web Push for the NAS web app (served at /app/). Shows what the gateway's web_push.py
// sends; tapping a notification opens (or focuses) the app. Registered by web/push.js,
// and the only service worker in this scope: the Flutter one is not registered at all
// (web/flutter_bootstrap.js), it would take the scope over.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let d = {};
  try {
    d = event.data ? event.data.json() : {};
  } catch (_) {
    d = { body: event.data ? event.data.text() : '' };
  }
  event.waitUntil(self.registration.showNotification(d.title || 'NAS', {
    body: d.body || '',
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    tag: d.tag || undefined,
    data: { url: d.url || '/app/' },
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || '/app/';
  event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
    for (const c of list) {
      if (c.url.includes('/app/') && 'focus' in c) return c.focus();
    }
    return self.clients.openWindow(url);
  }));
});
