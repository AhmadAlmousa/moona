from http.server import HTTPServer, SimpleHTTPRequestHandler
from functools import partial
from pathlib import Path
import sys

class WasmHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
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
