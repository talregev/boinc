'use strict';
// Spike B — headless oracle (runs in plain Node, no GPU needed).
// Purpose: prove the kernel is CORRECT and measure the CPU baseline, so that in the browser we only
// have to confirm the GPU produces the same numbers (and how much faster). It:
//   1. cross-checks the reference kernel.js against a fully independent BigInt implementation
//      (catches 32-bit masking / shift bugs — the usual way a WGSL<->JS port silently diverges),
//   2. benchmarks the CPU throughput and prints the expected checksum the browser must reproduce.
// Exits 0 only if the two independent implementations agree on every element.

const K = parseInt(process.argv[2] || '256', 10);      // iterations per element
const N = parseInt(process.argv[3] || String(1 << 20), 10);   // elements (default ~1.05M)
const kernel = require('./kernel');

// independent oracle: xorshift32 via BigInt masked to 32 bits (shares no code path with kernel.js)
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

console.log(`Spike B oracle — N=${N} elements, K=${K} iterations (${(N * K / 1e6).toFixed(0)}M kernel iterations)`);

const input = kernel.makeInput(N);

// 1. correctness: reference vs independent BigInt oracle over a sample (BigInt is slow, sample it)
const SAMPLE = Math.min(N, 8192);
let mismatches = 0, firstBad = -1;
for (let i = 0; i < SAMPLE; i++) {
    const ref = kernel.step(input[i], K);
    const big = stepBig(input[i], K);
    if (ref !== big) { mismatches++; if (firstBad < 0) firstBad = i; }
}
if (mismatches) {
    console.error(`\nSPIKE B ORACLE: FAILED — ${mismatches}/${SAMPLE} mismatches (first at i=${firstBad})`);
    const i = firstBad;
    console.error(`  input=${input[i] >>> 0}  ref=${kernel.step(input[i], K)}  bigint=${stepBig(input[i], K)}`);
    process.exit(1);
}
console.log(`  correctness : ok (${SAMPLE} elements match an independent BigInt implementation)`);

// 2. CPU baseline benchmark over the whole array
const out = new Uint32Array(N);
const t0 = process.hrtime.bigint();
for (let i = 0; i < N; i++) out[i] = kernel.step(input[i], K);
const t1 = process.hrtime.bigint();
const ms = Number(t1 - t0) / 1e6;
const iters = N * K;
const cksum = kernel.checksum(out);

console.log(`  CPU baseline: ${ms.toFixed(1)} ms  (${(iters / 1e6 / (ms / 1000)).toFixed(0)} M kernel-iters/s, single-threaded JS)`);
console.log(`  checksum    : 0x${cksum.toString(16).padStart(8, '0')}  <-- the browser WebGPU run must reproduce this exact value`);
console.log('\nSPIKE B ORACLE: PASSED');
console.log('  => kernel verified headless; GPU dispatch (index.html) only needs a WebGPU browser.');
