// client_worker.js — hosts the BOINC wasm client inside a dedicated Web Worker (the "daemon").
//
// The client no longer runs on the browser main thread; it runs here, in a Worker, exactly like the
// native core client runs as a background daemon. GUI RPC flows over postMessage — the faithful
// analog of the native localhost GUI-RPC socket:
//
//     page (GUI)  --{type:'rpc', id, req}-->  this Worker  --boinc_handle_gui_rpc()-->  reply
//     page (GUI)  <--{type:'rpc_reply', id, reply}--  this Worker
//
// The client's cooperative main loop (emscripten_set_main_loop) runs on this Worker's event loop;
// GUI RPC requests are serviced between iterations (single-threaded, so never reentrant — same
// invariant as the old on-page bridge). Science-app and benchmark Workers are nested Workers spawned
// from here. The client is a -pthread build (WasmFS's OPFS backend runs on a dedicated thread); its
// data dir is mounted on OPFS in C at main() start (client/main.cpp).

var Module = {
    arguments: [],
    print:    function (t) { postMessage({ type: 'stdout', text: t }); },
    printErr: function (t) { postMessage({ type: 'stderr', text: t }); },
    onAbort:  function (w) { postMessage({ type: 'abort',  text: String(w) }); },
    onExit:   function (c) { postMessage({ type: 'exit',   code: c }); },
    locateFile: function (p) { return p; },
};

// GUI RPC transport: run the request through the in-client bridge and post the reply back.
// boinc_handle_gui_rpc mallocs the reply buffer in C; we own it and must free it.
self.onmessage = function (e) {
    var m = e.data;
    if (!m || m.type !== 'rpc') return;
    var reply = '';
    try {
        var ptr = Module.ccall('boinc_handle_gui_rpc', 'number', ['string'], [m.req]);
        reply = Module.UTF8ToString(ptr);
        Module._free(ptr);
    } catch (err) {
        reply = '<boinc_gui_rpc_reply>\n<error>worker rpc failed: ' + err + '</error>\n</boinc_gui_rpc_reply>\n';
    }
    postMessage({ type: 'rpc_reply', id: m.id, reply: reply });
};

// Load + start the client (runs main() -> emscripten_set_main_loop on this Worker's thread).
// The webgpu_pre.js hook baked into boinc_client.js runs here in the Worker; navigator.gpu is
// available in a Worker context.
importScripts('boinc_client.js');
