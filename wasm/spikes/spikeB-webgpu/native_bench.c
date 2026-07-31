// Committed native benchmark for the xorshift32 kernel used across the wasm/WebGPU paths.
//
// Same kernel, same input, same fold, and the same target checksum (0x27a723a9) as
// wasm/gpu_app/gpu_app.cpp (the CPU reference + the WGSL shader) and spikeB's kernel.js — so the
// "CPU - native" rows in wasm/README.md are reproducible from a real *compiled* binary. (The earlier
// figures came from a Node/worker_threads oracle; this replaces that approximation.)
//
// Build:  cc -O2 -pthread native_bench.c -o native_bench   (or: ./build_native_bench.sh)
// Run:    ./native_bench [nthreads]   # default nthreads = online CPUs
// Prints M kernel-iters/s for 1 thread and for N threads; exits non-zero on a checksum mismatch.

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <pthread.h>

#define N (1u << 20)   // 1,048,576 elements
#define K 256          // xorshift iterations per element
#define TARGET 0x27a723a9u

typedef struct { uint32_t lo, hi, checksum; } slice_t;

static void* run_slice(void* arg) {
    slice_t* s = (slice_t*)arg;
    uint32_t c = 0;
    for (uint32_t i = s->lo; i < s->hi; i++) {
        uint32_t x = (uint32_t)((uint64_t)i * 2654435761ull + 1ull);   // Knuth multiplicative input
        for (int j = 0; j < K; j++) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; }  // xorshift32
        c ^= x;                                                        // XOR-fold
    }
    s->checksum = c;
    return NULL;
}

static double now_s(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}

static uint32_t run(int nthreads, double* secs) {
    if (nthreads < 1) nthreads = 1;
    if (nthreads > 256) nthreads = 256;
    pthread_t th[256];
    slice_t sl[256];
    uint32_t per = N / (uint32_t)nthreads;
    double t0 = now_s();
    for (int t = 0; t < nthreads; t++) {
        sl[t].lo = (uint32_t)t * per;
        sl[t].hi = (t == nthreads - 1) ? N : (uint32_t)(t + 1) * per;
        sl[t].checksum = 0;
        pthread_create(&th[t], NULL, run_slice, &sl[t]);
    }
    uint32_t c = 0;
    for (int t = 0; t < nthreads; t++) { pthread_join(th[t], NULL); c ^= sl[t].checksum; }
    *secs = now_s() - t0;
    return c;
}

int main(int argc, char** argv) {
    int maxthreads = (argc > 1) ? atoi(argv[1]) : 0;
    if (maxthreads <= 0) {
        long n = sysconf(_SC_NPROCESSORS_ONLN);
        maxthreads = (n > 0) ? (int)n : 4;
    }

    double s1;
    uint32_t c1 = run(1, &s1);
    printf("kernel: xorshift32  N=%u  K=%d  checksum=0x%08x  (expect 0x%08x)\n", N, K, c1, TARGET);
    if (c1 != TARGET) { printf("FAIL: checksum mismatch\n"); return 1; }
    printf("CPU native   1 thread : %6.0f M kernel-iters/s  (%.1f ms)\n",
           (double)N * K / 1e6 / s1, s1 * 1000.0);

    double sN;
    uint32_t cN = run(maxthreads, &sN);
    printf("CPU native %3d threads: %6.0f M kernel-iters/s  (%.1f ms)  checksum=0x%08x\n",
           maxthreads, (double)N * K / 1e6 / sN, sN * 1000.0, cN);

    return (cN == TARGET) ? 0 : 1;
}
