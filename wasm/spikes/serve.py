#!/usr/bin/env python3
# Dev server for the wasm spikes AND the Phase 2 browser client harness.
#   - COOP/COEP: cross-origin isolation for SharedArrayBuffer / threads.
#   - CORS (Access-Control-Allow-Origin: *) + OPTIONS preflight: lets the wasm client's
#     emscripten_fetch reach this server cross-origin (the Phase 2d CORS proof).
#   - POST /report  -> append JSON to runs.jsonl (spike pages report results here).
#   - POST <other>  -> test mock for the client's HTTP_OP POST path (e.g. the account-manager
#     RPC posts <acct_mgr_request> to /rpc.php): log the received body to runs.jsonl (proof the
#     POST body was transmitted) and return a canned <acct_mgr_reply>.
#
# Usage:  python3 serve.py [port]
import json
import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

RUNS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'runs.jsonl')

class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cross-Origin-Resource-Policy', 'cross-origin')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def do_OPTIONS(self):          # CORS preflight
        self.send_response(204)
        self.end_headers()

    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(n)
        if self.path == '/report':
            with open(RUNS, 'ab') as f:
                f.write(body + b'\n')
            self.send_response(204)
            self.end_headers()
            return
        # test mock for the client's HTTP_OP POST path: record the body, return a canned reply
        rec = {'tag': 'server-post', 'path': self.path, 'len': len(body),
               'head': body[:240].decode('utf-8', 'replace')}
        with open(RUNS, 'ab') as f:
            f.write((json.dumps(rec) + '\n').encode())
        print('[POST]', self.path, len(body), 'bytes')
        reply = (b'<acct_mgr_reply>\n<name>WASM Test AM</name>\n'
                 b'<error_num>0</error_num>\n</acct_mgr_reply>\n')
        self.send_response(200)
        self.send_header('Content-Type', 'text/xml')
        self.send_header('Content-Length', str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    print(f'serving {os.path.dirname(RUNS)} on http://localhost:{port}/  '
          f'(COOP/COEP + CORS, POST /report + POST mock)')
    ThreadingHTTPServer(('0.0.0.0', port), Handler).serve_forever()
