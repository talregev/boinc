// Standalone CPU benchmark for the wasm client, run in a Web Worker — the browser analog of the
// native fork'd benchmark child (client/cs_benchmark.cpp). It runs the same Whetstone (FP) and
// Dhrystone (integer) cores as the native client, then prints a single result line that the client's
// benchmark-Worker glue parses and postMessage()s back.
//
// Two wasm adaptations:
//  - timing uses wall-clock (lib/util.cpp boinc_calling_thread_cpu_time on WASM): a dedicated Worker
//    only computes, so wall-clock ~= CPU time, and emscripten's getrusage() is a constant stub.
//  - benchmark_time_to_stop() is normally driven by the parent process removing a file after a fixed
//    duration; here (no parent) we stop each test after a fixed wall-clock duration.
#include <cstdio>
#include "cpu_benchmark.h"
#include "util.h"       // dtime()

#define MIN_CPU_TIME    1.0    // whetstone/dhrystone require the run to last at least this long
#define BENCH_DURATION  1.5    // run each test this long (wall-clock); must exceed MIN_CPU_TIME

// Natively the child waits for the parent to signal start (create a file); in the Worker there is
// no parent, so start immediately.
void benchmark_wait_to_start(int) {}

// Wall-clock replacement for the native (file-driven) benchmark_time_to_stop(). Runs each test
// (BM_TYPE_FP=0, BM_TYPE_INT=1) for BENCH_DURATION seconds.
bool benchmark_time_to_stop(int which) {
    static double start[2] = {0, 0};
    static bool started[2] = {false, false};
    if (which < 0 || which > 1) return true;
    if (!started[which]) { start[which] = dtime(); started[which] = true; return false; }
    return (dtime() - start[which]) >= BENCH_DURATION;
}

int main() {
    double p_fpops = 0, fp_time = 0;
    double vax_mips = 0, int_loops = 0, int_time = 0;

    whetstone(p_fpops, fp_time, MIN_CPU_TIME);      // FP ops/sec
    dhrystone(vax_mips, int_loops, int_time, MIN_CPU_TIME);
    double p_iops = vax_mips * 1e6;                 // integer ops/sec
    double p_membw = 1e9;                           // memory bandwidth: nominal, as the native client

    printf("BENCHMARK_RESULT fpops=%e iops=%e membw=%e\n", p_fpops, p_iops, p_membw);
    fflush(stdout);
    return 0;
}
