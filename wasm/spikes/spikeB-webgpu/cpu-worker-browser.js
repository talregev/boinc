'use strict';
// Spike B — browser CPU worker (mirror of cpu-worker.js for Node). Computes the xorshift32 kernel
// over its slice of the shared input and returns a partial checksum, so the page can build a fair
// all-cores CPU baseline to compare against the GPU. Needs cross-origin isolation (SharedArrayBuffer).
importScripts('kernel.js');

self.postMessage('ready');               // signal load complete, so timing can exclude spawn cost
self.onmessage = (e) => {
    const { sab, start, end, K } = e.data;
    const input = new Uint32Array(sab);
    let partial = 0;
    for (let i = start; i < end; i++) partial = (partial ^ SpikeKernel.step(input[i], K)) >>> 0;
    self.postMessage(partial >>> 0);
};
