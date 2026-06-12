from http.server import HTTPServer, SimpleHTTPRequestHandler
from functools import partial
from pathlib import Path
import sys

class WasmHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        # NOTE: We deliberately do NOT set cross-origin isolation headers
        # (Cross-Origin-Opener-Policy / Cross-Origin-Embedder-Policy). The web
        # app is the default JavaScript/CanvasKit build, which needs no
        # SharedArrayBuffer/threads. Under COEP `require-corp`, Chrome blocks
        # every cross-origin subresource that lacks CORP headers — Firebase,
        # Appwrite, and the FCM service worker's gstatic importScripts — so the
        # app loaded only in (more lenient) Firefox. Removing them fixes Chrome.
        # Force revalidation so browsers/proxies never serve a stale bundle
        # (If-Modified-Since still yields cheap 304s for unchanged files).
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

WasmHandler.extensions_map.update({
    '.wasm': 'application/wasm',
})

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
default_root = Path(__file__).resolve().parent / 'build' / 'web'
root = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else default_root
if not root.exists():
    root = Path.cwd()

handler = partial(WasmHandler, directory=str(root))
print(f"Serving {root} on http://localhost:{port} with Wasm headers...")
HTTPServer(('0.0.0.0', port), handler).serve_forever()
