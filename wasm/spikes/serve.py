#!/usr/bin/env python3
# Static file server for the Phase 0 spikes, with the headers browsers require:
#   COOP/COEP  -> cross-origin isolation, needed for SharedArrayBuffer (Spike A) and wasm threads.
#   (WebGPU in Spike B does NOT need these, but serving over http avoids file:// quirks.)
#
# Usage:  python3 serve.py [port]      then open  http://localhost:8000/spikeA-ipc/
#                                                  http://localhost:8000/spikeB-webgpu/
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cross-Origin-Resource-Policy', 'same-origin')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    print(f'serving {__file__.rsplit("/", 1)[0] or "."} on http://localhost:{port}/  (COOP/COEP on)')
    ThreadingHTTPServer(('0.0.0.0', port), Handler).serve_forever()
