// This file is part of BOINC.  https://boinc.berkeley.edu
//
// --pre-js for the WebAssembly client: make the BOINC data directory persist across
// page reloads by backing it with IDBFS (IndexedDB). IDBFS works on the main thread,
// which the current single-threaded client needs. (OPFS is faster but its synchronous
// access handles are Worker-only; we switch to OPFS once the client runs in a Worker.)
//
// The data dir is the client's working directory. We mount IDBFS at /boinc_data, load
// any previously-persisted contents before main() runs, chdir into it, and flush back
// to IndexedDB periodically so client_state.xml, projects, and tasks survive reloads.

Module.preRun = Module.preRun || [];
Module.preRun.push(function () {
    // Persist only in a browser/Worker: IDBFS needs IndexedDB, which is absent under
    // Node/CI — there MEMFS is fine and blocking on syncfs() would hang startup.
    if (typeof indexedDB === 'undefined') return;
    try {
        FS.mkdir('/boinc_data');
        FS.mount(IDBFS, {}, '/boinc_data');
        FS.chdir('/boinc_data');
        // async load of the persisted image; hold startup until it completes
        addRunDependency('boinc-idbfs-load');
        FS.syncfs(true, function (err) {
            if (err) console.warn('BOINC: IDBFS load error:', err);
            // wasm-build default: accept unsigned project apps. The browser has no code-signing
            // infrastructure, and apps are fetched from the (CORS-scoped) project over HTTPS.
            try {
                if (!FS.analyzePath('/boinc_data/cc_config.xml').exists) {
                    FS.writeFile('/boinc_data/cc_config.xml',
                        '<cc_config>\n<options>\n<unsigned_apps_ok>1</unsigned_apps_ok>\n</options>\n</cc_config>\n');
                }
            } catch (e) { console.warn('BOINC: cc_config write failed:', e); }
            removeRunDependency('boinc-idbfs-load');
        });
    } catch (e) {
        console.warn('BOINC: IDBFS mount failed, running with a non-persistent data dir:', e);
    }
});

Module.postRun = Module.postRun || [];
Module.postRun.push(function () {
    // flush MEMFS view -> IndexedDB every few seconds so state survives reload/crash
    setInterval(function () {
        try { FS.syncfs(false, function () {}); } catch (e) {}
    }, 5000);
    // best-effort final flush when the tab goes away
    if (typeof addEventListener === 'function') {
        addEventListener('pagehide', function () {
            try { FS.syncfs(false, function () {}); } catch (e) {}
        });
    }
});
