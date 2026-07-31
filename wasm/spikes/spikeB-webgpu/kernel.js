// Spike B — the reference kernel, shared by the Node oracle and the browser WebGPU harness.
// A per-element xorshift32 RNG iterated K times. Chosen because it is (a) compute-heavy and
// embarrassingly parallel like a real BOINC search, and (b) EXACT in both WGSL `u32` and JS 32-bit
// bitwise ops — so the GPU result can be checked bit-for-bit against this CPU reference.
//
// Works in Node (module.exports) and in the browser (window.SpikeKernel).
(function (root, factory) {
    const api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    else root.SpikeKernel = api;
})(typeof self !== 'undefined' ? self : this, function () {
    'use strict';

    // one element, K iterations of xorshift32 — mirrors compute.wgsl exactly
    function step(x, k) {
        x = x >>> 0;
        for (let j = 0; j < k; j++) {
            x ^= x << 13;  x >>>= 0;
            x ^= x >>> 17; x >>>= 0;
            x ^= x << 5;   x >>>= 0;
        }
        return x >>> 0;
    }

    // deterministic input, identical on CPU and GPU (uploaded verbatim to the GPU buffer)
    function makeInput(n) {
        const a = new Uint32Array(n);
        for (let i = 0; i < n; i++) a[i] = ((i * 2654435761) + 1) >>> 0;   // Knuth multiplicative
        return a;
    }

    // fold an output array to a single 32-bit checksum for easy GPU-vs-CPU comparison
    function checksum(out) {
        let c = 0;
        for (let i = 0; i < out.length; i++) c = (c ^ out[i]) >>> 0;
        return c >>> 0;
    }

    return { step, makeInput, checksum };
});
