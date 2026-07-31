'use strict';
// Spike B — headless oracle (runs in plain Node, no GPU needed).
// Proves the kernel is CORRECT and measures BOTH CPU baselines (single-thread and all-cores), so
// that in the browser we only have to confirm the GPU matches and by how much. It:
//   1. cross-checks the reference kernel.js against an independent BigInt implementation,
//   2. benchmarks single-thread CPU, then an all-cores CPU baseline (worker_threads) for a FAIR
//      GPU-vs-CPU comparison, verifying both reproduce the same checksum,
//   3. prints the checksum the browser WebGPU run must reproduce.
// Exits 0 only if every implementation agrees.

const os = require('os');
const path = require('path');
const { Worker } = require('worker_threads');
const kernel = require('./kernel');

const K = parseInt(process.argv[2] || '256', 10);              // iterations per element
const N = parseInt(process.argv[3] || String(1 << 20), 10);   // elements (default ~1.05M)

// independent oracle: xorshift32 via BigInt masked to 32 bits (shares no code with kernel.js)
const M = (1n << 32n) - 1n;
function stepBig(x0, k) {
    let x = BigInt(x0 >>> 0) & M;
    for (let i = 0; i < k; i++) {
        x = (x ^ ((x << 13n) & M)) & M;
        x = (x ^ (x >> 17n)) & M;
        x = (x ^ ((x << 5n) & M)) & M;
    }
    return Number(x & M) >>> 0;
}

// all-cores CPU baseline: split the shared input across P worker threads, XOR-fold partial checksums
async function parallelBaseline(input, k) {
    const P = Math.max(1, os.cpus().length);
    const sab = new SharedArrayBuffer(input.length * 4);
    new Uint32Array(sab).set(input);
    const chunk = Math.ceil(input.length / P);
    const workers = [];
    for (let p = 0; p < P; p++) {
        const start = p * chunk, end = Math.min(input.length, start + chunk);
        workers.push(new Worker(path.join(__dirname, 'cpu-worker.js'), { workerData: { sab, start, end, K: k } }));
    }
    await Promise.all(workers.map(w => new Promise(r => w.once('online', r))));   // exclude spawn cost
    const results = workers.map(w => new Promise((res, rej) => { w.once('message', res); w.once('error', rej); }));
    const t0 = process.hrtime.bigint();
    workers.forEach(w => w.postMessage('go'));
    const partials = await Promise.all(results);
    const ms = Number(process.hrtime.bigint() - t0) / 1e6;
    await Promise.all(workers.map(w => w.terminate()));
    const cksum = partials.reduce((a, b) => (a ^ b) >>> 0, 0) >>> 0;
    return { ms, cksum, P };
}

async function main() {
    console.log(`Spike B oracle — N=${N} elements, K=${K} iterations (${(N * K / 1e6).toFixed(0)}M kernel iterations)`);
    const input = kernel.makeInput(N);

    // 1. correctness vs independent BigInt oracle (BigInt is slow -> sample)
    const SAMPLE = Math.min(N, 8192);
    let firstBad = -1;
    for (let i = 0; i < SAMPLE; i++) {
        if (kernel.step(input[i], K) !== stepBig(input[i], K)) { firstBad = i; break; }
    }
    if (firstBad >= 0) {
        const i = firstBad;
        console.error(`\nSPIKE B ORACLE: FAILED — mismatch at i=${i}: input=${input[i] >>> 0} ref=${kernel.step(input[i], K)} bigint=${stepBig(input[i], K)}`);
        process.exit(1);
    }
    console.log(`  correctness    : ok (${SAMPLE} elements match an independent BigInt implementation)`);

    // 2a. single-thread CPU baseline
    const out = new Uint32Array(N);
    let t0 = process.hrtime.bigint();
    for (let i = 0; i < N; i++) out[i] = kernel.step(input[i], K);
    const stMs = Number(process.hrtime.bigint() - t0) / 1e6;
    const cksum = kernel.checksum(out);

    // 2b. all-cores CPU baseline
    const mt = await parallelBaseline(input, K);
    if (mt.cksum !== cksum) {
        console.error(`\nSPIKE B ORACLE: FAILED — multi-thread checksum 0x${mt.cksum.toString(16)} != single-thread 0x${cksum.toString(16)}`);
        process.exit(1);
    }

    const iters = N * K;
    const rate = ms => (iters / 1e6 / (ms / 1000)).toFixed(0);
    console.log(`  CPU  1 thread  : ${stMs.toFixed(1)} ms  (${rate(stMs)} M kernel-iters/s)`);
    console.log(`  CPU ${String(mt.P).padStart(2)} threads : ${mt.ms.toFixed(1)} ms  (${rate(mt.ms)} M kernel-iters/s)  <-- fair CPU baseline for GPU comparison`);
    console.log(`  scaling        : ${(stMs / mt.ms).toFixed(1)}x across ${mt.P} cores`);
    console.log(`  checksum       : 0x${cksum.toString(16).padStart(8, '0')}  <-- the browser WebGPU run must reproduce this`);
    console.log('\nSPIKE B ORACLE: PASSED');
    console.log('  => kernel verified headless (1-thread == all-cores); GPU dispatch (index.html) needs a WebGPU browser.');
}

main().catch(e => { console.error('\nSPIKE B ORACLE: FAILED —', e && e.stack || e); process.exit(1); });
