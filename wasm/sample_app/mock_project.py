#!/usr/bin/env python3
# Phase 7: a minimal mock BOINC project + scheduler so the wasm client can attach, get one task,
# download the (unsigned) wasm app + input, and run it. Runs on its own origin (default :8100) so
# it's cross-origin from the client page — exercising the CORS path proven in Phase 2d.
#
#   GET  /                      -> master file (HTML with the <scheduler> URL)
#   POST /cgi                   -> scheduler_reply: one app + wasm app_version + workunit + result
#   GET  /download/<file>       -> app.js / app.wasm / input.txt
#   POST /upload                -> accept the result upload
#
# Usage: python3 mock_project.py [port] [host_url]   (host_url defaults to http://localhost:8100/)
import os, re, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8100
BASE = sys.argv[2] if len(sys.argv) > 2 else f'http://localhost:{PORT}/'
HERE = os.path.dirname(os.path.abspath(__file__))

MASTER = f'''<html><head><title>WASM Test Project</title></head><body>
<!-- BOINC scheduler locations -->
<scheduler>{BASE}cgi</scheduler>
</body></html>'''

def file_bytes(name):
    try:
        with open(os.path.join(HERE, name), 'rb') as f: return f.read()
    except OSError:
        return None

def scheduler_reply(req_body):
    m = re.search(r'<platform_name>([^<]+)</platform_name>', req_body)
    platform = m.group(1) if m else 'i686-pc-linux-gnu'
    appjs = file_bytes('app.js') or b''
    appwasm = file_bytes('app.wasm') or b''
    inp = b'wasm input payload\n'
    deadline = int(time.time()) + 7*86400
    return f'''<?xml version="1.0" encoding="ISO-8859-1"?>
<scheduler_reply>
<scheduler_version>80300</scheduler_version>
<request_delay>3</request_delay>
<hostid>1</hostid>
<project_name>WASM Test Project</project_name>
<user_name>tester</user_name>
<userid>1</userid>
<team_name></team_name>
<host_venue></host_venue>
<code_sign_key>
</code_sign_key>
<app>
<name>sample</name>
<user_friendly_name>WASM Sample</user_friendly_name>
</app>
<file_info>
<name>app.js</name>
<url>{BASE}download/app.js</url>
<executable/>
<nbytes>{len(appjs)}</nbytes>
</file_info>
<file_info>
<name>app.wasm</name>
<url>{BASE}download/app.wasm</url>
<nbytes>{len(appwasm)}</nbytes>
</file_info>
<file_info>
<name>input.txt</name>
<url>{BASE}download/input.txt</url>
<nbytes>{len(inp)}</nbytes>
</file_info>
<file_info>
<name>wu_1_0_out</name>
<generated_locally/>
<max_nbytes>1000000</max_nbytes>
<upload_url>{BASE}upload</upload_url>
<upload_when_present/>
</file_info>
<app_version>
<app_name>sample</app_name>
<version_num>100</version_num>
<platform>{platform}</platform>
<avg_ncpus>1</avg_ncpus>
<flops>1000000000</flops>
<file_ref>
<file_name>app.js</file_name>
<main_program/>
</file_ref>
<file_ref>
<file_name>app.wasm</file_name>
</file_ref>
</app_version>
<workunit>
<name>wu_1</name>
<app_name>sample</app_name>
<version_num>100</version_num>
<rsc_fpops_est>1000000000</rsc_fpops_est>
<rsc_fpops_bound>1000000000000</rsc_fpops_bound>
<rsc_memory_bound>134217728</rsc_memory_bound>
<rsc_disk_bound>134217728</rsc_disk_bound>
<command_line></command_line>
<file_ref>
<file_name>input.txt</file_name>
<open_name>in</open_name>
</file_ref>
</workunit>
<result>
<name>wu_1_0</name>
<wu_name>wu_1</wu_name>
<report_deadline>{deadline}</report_deadline>
<platform>{platform}</platform>
<version_num>100</version_num>
<plan_class></plan_class>
<file_ref>
<file_name>wu_1_0_out</file_name>
<open_name>out</open_name>
</file_ref>
</result>
</scheduler_reply>
'''

class H(BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Cross-Origin-Resource-Policy', 'cross-origin')
    def _send(self, code, body, ctype='text/xml'):
        self.send_response(code); self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body))); self._cors(); self.end_headers()
        if body: self.wfile.write(body)
    def do_OPTIONS(self): self.send_response(204); self._cors(); self.end_headers()
    def log_message(self, *a): print('[mock]', self.command, self.path)
    def do_GET(self):
        if self.path in ('/', '/index.html'):
            self._send(200, MASTER.encode(), 'text/html'); return
        if self.path.startswith('/download/'):
            name = self.path.split('/download/', 1)[1]
            if name == 'input.txt': self._send(200, b'wasm input payload\n', 'text/plain'); return
            b = file_bytes(name)
            if b is not None: self._send(200, b, 'application/octet-stream'); return
        self._send(404, b'not found', 'text/plain')
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0)); body = self.rfile.read(n).decode('utf-8', 'replace')
        if self.path.rstrip('/').endswith('/cgi') or self.path == '/cgi':
            print('[mock] scheduler_request %d bytes' % n)
            self._send(200, scheduler_reply(body).encode()); return
        if self.path.rstrip('/').endswith('/upload'):
            self._send(200, b'<data_server_reply><status>0</status></data_server_reply>'); return
        self._send(404, b'not found', 'text/plain')

if __name__ == '__main__':
    print(f'mock project on {BASE} (scheduler {BASE}cgi)')
    ThreadingHTTPServer(('0.0.0.0', PORT), H).serve_forever()
