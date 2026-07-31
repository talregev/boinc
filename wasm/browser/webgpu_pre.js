// This file is part of BOINC.  https://boinc.berkeley.edu
//
// --pre-js for the WebAssembly client: detect the WebGPU adapter before main() runs, so the
// client can register it as a coproc at GPU-detection time (client/gpu_detect.cpp COPROCS::get)
// instead of the native fork/exec probe, which can't work in a browser.
//
// navigator.gpu presence is synchronous; the adapter's name (vendor/architecture/device) comes
// from requestAdapter(), which is async. We kick that off here FIRE-AND-FORGET — deliberately
// WITHOUT a run dependency — so it runs concurrently with the IDBFS load that already gates
// startup (persist_pre.js) and never delays boot on the GPU. By the time C reads
// Module.webgpuAdapter it is usually populated; if not, the client fills the name in later.

Module.preRun = Module.preRun || [];
Module.preRun.push(function () {
    Module.webgpuAdapter = {
        present: (typeof navigator !== 'undefined' && !!navigator.gpu),
        name: ''
    };
    if (!Module.webgpuAdapter.present) return;
    try {
        navigator.gpu.requestAdapter({ powerPreference: 'high-performance' }).then(function (a) {
            if (!a) { Module.webgpuAdapter.present = false; return; }
            var info = {};
            try { info = a.info || {}; } catch (e) {}
            Module.webgpuAdapter.name =
                [info.vendor || '?', info.architecture || '?', info.device || '?'].join('/');
        }).catch(function () { /* leave name empty; presence still true */ });
    } catch (e) { /* requestAdapter threw synchronously (very old impls); keep presence */ }
});
