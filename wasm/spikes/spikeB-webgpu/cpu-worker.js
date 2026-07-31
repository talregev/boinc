'use strict';
// Spike B polish — one CPU worker thread. Computes the xorshift32 kernel over its slice of the
// shared input and returns a partial checksum (XOR-fold). Used to build a fair, all-cores CPU
// baseline so the GPU-vs-CPU speedup isn't measured against a single JS thread.
const { parentPort, workerData } = require('worker_threads');
const kernel = require('./kernel');

const input = new Uint32Array(workerData.sab);
const { start, end, K } = workerData;

parentPort.once('message', () => {          // wait for "go" so timing excludes spawn cost
    let partial = 0;
    for (let i = start; i < end; i++) partial = (partial ^ kernel.step(input[i], K)) >>> 0;
    parentPort.postMessage(partial >>> 0);
});
