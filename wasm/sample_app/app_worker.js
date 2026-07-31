// Phase 3 Worker glue for the wasm science app. The client creates the app in a Web Worker and
// posts it the shared SharedArrayBuffer; we expose it as Module.boincShm (what lib/app_ipc.cpp's
// SAB code uses) and hold startup until it arrives. App stdout is forwarded to the page.
var g_sab = null;
onmessage = function (e) {
    if (e.data && e.data.boincShm) {
        g_sab = e.data.boincShm;
        if (Module.onShm) Module.onShm();
    }
};
var Module = {
    print:    function (t) { postMessage({ log: t }); },
    printErr: function (t) { postMessage({ log: t }); },
    onExit:   function (c) { postMessage({ exit: c }); },
    preRun: [function () {
        if (g_sab) { Module.boincShm = new Uint8Array(g_sab); return; }
        addRunDependency('boinc-shm');           // wait for the client's SAB before main()
        Module.onShm = function () {
            Module.boincShm = new Uint8Array(g_sab);
            removeRunDependency('boinc-shm');
        };
    }],
};
importScripts('app.js');
