#!/usr/bin/env python3
# Static file server for the Phase 0 spikes, with the headers browsers require:
#   COOP/COEP  -> cross-origin isolation, needed for SharedArrayBuffer (Spike A) and wasm threads.
#   (WebGPU in Spike B does NOT need these, but serving over http avoids file:// quirks.)
#
# Also exposes POST /report : the spike pages POST their final results here as JSON, and the server
# appends them to runs.jsonl next to this script. That lets the tooling (and Claude) read what a real
# browser actually produced — GPU timings, checksums, pass/fail — without copy-paste.
#
# Usage:  python3 serve.py [port]      then open  http://localhost:8000/spikeA-ipc/
#                                                  http://localhost:8000/spikeB-webgpu/
import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

RUNS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'runs.jsonl')

class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cross-Origin-Resource-Policy', 'same-origin')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def do_POST(self):
        if self.path == '/report':
            n = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(n)
            with open(RUNS, 'ab') as f:
                f.write(body + b'\n')
            print('[report]', body.decode('utf-8', 'replace')[:500])
            self.send_response(204)
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    print(f'serving {os.path.dirname(RUNS)} on http://localhost:{port}/  (COOP/COEP on, POST /report -> runs.jsonl)')
    ThreadingHTTPServer(('0.0.0.0', port), Handler).serve_forever()
