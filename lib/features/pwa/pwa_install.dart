/// Entry point for the PWA install prompt.
///
/// Resolves to the web impl in the browser and a no-op stub elsewhere. Import
/// this file (never the `_web`/`_stub` variants directly).
library;

export 'pwa_install_stub.dart'
    if (dart.library.js_interop) 'pwa_install_web.dart';
