// A real BOINC science app for the wasm client, using the standard libboinc_api:
// boinc_init / boinc_resolve_filename / boinc_fopen / boinc_fraction_done / boinc_finish.
// This proves *arbitrary* project apps run in the browser — nothing here is wasm-specific or
// hand-wired to the SharedArrayBuffer. The API's wasm port (api/boinc_api.cpp) attaches to the
// SAB the client handed the Worker, drives progress synchronously from boinc_fraction_done(),
// and on boinc_finish() bridges the output file(s) back to the client.
#include <cstdio>
#include <cstring>
#include "boinc_api.h"
#include "filesys.h"

int main() {
    int retval = boinc_init();
    if (retval) {
        fprintf(stderr, "sample_app: boinc_init failed: %d\n", retval);
        return retval;
    }

    // Resolve and read the input file (logical name "in"; the client copied it into the slot).
    char in_path[512], out_path[512];
    boinc_resolve_filename("in", in_path, sizeof(in_path));
    boinc_resolve_filename("out", out_path, sizeof(out_path));

    char input[4096];
    size_t n = 0;
    FILE* f = boinc_fopen(in_path, "r");
    if (f) { n = fread(input, 1, sizeof(input) - 1, f); fclose(f); }
    input[n] = 0;
    fprintf(stderr, "sample_app: read %zu input bytes from '%s'\n", n, in_path);

    // Crunch: report fraction_done across the run. Each call pushes progress to the client
    // (over the SAB) and polls process control (suspend/resume/quit).
    const int STEPS = 50;
    for (int step = 0; step <= STEPS; step++) {
        volatile double acc = 0;
        for (int i = 0; i < 8000000; i++) acc += i * 0.5;
        boinc_fraction_done((double)step / STEPS);
    }

    // Write the output file (logical name "out"); boinc_finish() bridges it to the client.
    FILE* of = boinc_fopen(out_path, "w");
    if (of) {
        fprintf(of, "wasm result: crunched %d steps over %zu input bytes\ninput was: %s",
            STEPS, n, input);
        fclose(of);
    }
    fprintf(stderr, "sample_app: wrote output to '%s'; calling boinc_finish\n", out_path);

    boinc_finish(0);   // does not return
    return 0;
}
