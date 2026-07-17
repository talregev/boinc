// Phase 3 minimal wasm science app. It uses the real SAB-backed APP_CLIENT_SHM
// (lib/app_ipc.cpp) to report fraction_done to the client and to honour a <quit/>
// process-control message — proving app<->client IPC across two separate wasm modules.
// The Worker glue (app_worker.js) sets Module.boincShm from the SharedArrayBuffer the
// client hands over; boinc_wasm_shm_setup() then attaches this app to it.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <emscripten.h>
#include "app_ipc.h"

int main() {
    APP_CLIENT_SHM shm;
    shm.shm = (SHARED_MEM*)malloc(sizeof(SHARED_MEM));
    boinc_wasm_shm_setup(shm.shm);     // Module.boincShm already set by the Worker glue
    printf("sample_app: attached to shared memory; crunching\n");

    char cmd[MSG_CHANNEL_SIZE], buf[256];
    const int STEPS = 100;
    for (int step = 0; step <= STEPS; step++) {
        // do a chunk of "science" (busy work so a step takes ~tens of ms)
        volatile double acc = 0;
        for (int i = 0; i < 8000000; i++) acc += i * 0.5;

        // report progress (drop silently if the client hasn't read the last one yet)
        double frac = (double)step / STEPS;
        snprintf(buf, sizeof(buf), "<fraction_done>%f</fraction_done>", frac);
        shm.shm->app_status.send_msg(buf);

        // honour process-control (quit)
        if (shm.shm->process_control_request.get_msg(cmd) && strstr(cmd, "<quit/>")) {
            printf("sample_app: received quit at fraction_done=%f\n", frac);
            shm.shm->app_status.send_msg_overwrite("<state>exited</state>");
            return 0;
        }
    }
    printf("sample_app: finished\n");
    // Report the result + signal completion over the SAB. This is robust: it does not rely on the
    // Worker exiting / emscripten onExit. trickle_up carries the output (open_name "out");
    // process_control_reply carries <finished/>, which the client reaps in check_app_exited().
    char output[256];
    snprintf(output, sizeof(output), "wasm result: crunched %d steps\n", STEPS);
    shm.shm->app_status.send_msg_overwrite("<fraction_done>1.000000</fraction_done>");
    shm.shm->trickle_up.send_msg_overwrite(output);
    shm.shm->process_control_reply.send_msg_overwrite("<finished/>");
    printf("sample_app: signaled completion via SAB\n");
    return 0;
}
