// Firebase Cloud Messaging service worker for the Moona PWA.
//
// firebase_messaging (web) auto-registers this file from the web root. It runs
// in the background so the browser can display push notifications when the PWA
// is closed or not focused. Uses the compat SDK (the form FCM's web SW expects).
//
// Config mirrors lib/firebase_options.dart (web). These are public client
// identifiers, not secrets.
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyALifOCIv0rR3ECDDxkIW14RI4V0v2WYNc',
  appId: '1:57956565699:web:b72aa0f6c576e2497dd876',
  messagingSenderId: '57956565699',
  projectId: 'moona-71bf8',
  authDomain: 'moona-71bf8.firebaseapp.com',
  storageBucket: 'moona-71bf8.firebasestorage.app',
  measurementId: 'G-VKQ0Z6EVE9',
});

const messaging = firebase.messaging();

// Background data+notification messages are shown by the browser automatically
// for `notification` payloads. This handler is a fallback for data-only sends
// and keeps the title/body consistent with the rest of the app ("Moona").
messaging.onBackgroundMessage(function (payload) {
  const notification = payload.notification || {};
  const title = notification.title || 'Moona';
  self.registration.showNotification(title, {
    body: notification.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: payload.data || {},
  });
});

// Focus/open the app when a notification is tapped.
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (list) {
      for (const client of list) {
        if ('focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow('/');
    })
  );
});
