// CI-only shim. Node has no XMLHttpRequest, which emscripten_fetch (-sFETCH) references on its
// uncached path; the browser build never needs this. We don't want real networking in the headless
// selftest — every request should simply fail as "offline", which the client already handles as
// ERR_CONNECT (see client/http_curl.cpp got_select). Loaded via `node -r ./wasm/ci_xhr_shim.js`;
// NEVER bundled into the shipped boinc_client.js/.wasm.
globalThis.XMLHttpRequest = class {
  open() {} setRequestHeader() {} abort() {}
  addEventListener(t, f) { if (t === 'error') this._err = f; if (t === 'loadend') this._end = f; }
  send() {
    this.readyState = 4; this.status = 0; this.response = null; this.responseText = '';
    setTimeout(() => {
      this.onreadystatechange && this.onreadystatechange();
      this._err && this._err(new Event('error'));
      this.onerror && this.onerror(new Event('error'));
      this._end && this._end();
    }, 0);
  }
};
