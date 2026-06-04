{{flutter_js}}
{{flutter_build_config}}

async function clearOldFlutterServiceWorker() {
  if (!('serviceWorker' in navigator)) return false;

  const registrations = await navigator.serviceWorker.getRegistrations();
  await Promise.all(registrations.map((registration) => registration.unregister()));

  if ('caches' in window) {
    const keys = await caches.keys();
    await Promise.all(
      keys
        .filter((key) => key.startsWith('flutter-app-cache'))
        .map((key) => caches.delete(key)),
    );
  }

  if (navigator.serviceWorker.controller) {
    window.location.reload();
    return true;
  }

  return false;
}

clearOldFlutterServiceWorker()
  .catch((error) => {
    console.warn('Could not clear old Flutter service worker:', error);
    return false;
  })
  .then((reloaded) => {
    if (reloaded) return;
    _flutter.loader.load({
      config: {
        // Serve the CanvasKit wasm from our own origin (faster, offline-friendly).
        canvasKitBaseUrl: 'canvaskit/',
        // Leave fontFallbackBaseUrl at its default so CanvasKit can fetch the Noto
        // fallback fonts on demand — this is what renders emoji (category icons)
        // and any glyph missing from Cairo/Nunito. An empty value disables that
        // and was why emoji + some Arabic glyphs were blank.
      },
    });
  });
