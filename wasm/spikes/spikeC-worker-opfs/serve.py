#!/usr/bin/env python3
# COOP/COEP server (for crossOriginIsolated -> SharedArrayBuffer -> -pthread) that also
# captures the spike's POST /report so we can read the OPFS result headlessly.
import http.server, socketserver, sys, os
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()
    def guess_type(self, path):
        if path.endswith('.wasm'): return 'application/wasm'
        return super().guess_type(path)
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(n).decode('utf-8', 'replace')
        open('result.json', 'w').write(body)
        sys.stderr.write('\n[REPORT] ' + body + '\n'); sys.stderr.flush()
        self.send_response(200); self.send_header('Access-Control-Allow-Origin','*'); self.end_headers()
        self.wfile.write(b'ok')
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(('0.0.0.0', PORT), H) as httpd:
    sys.stderr.write(f'serving on {PORT}\n'); sys.stderr.flush()
    httpd.serve_forever()
