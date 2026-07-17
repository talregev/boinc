// Phase 2d.2 de-risk: prove emscripten_fetch (the browser HTTP transport) works from
// wasm C before wiring it into the client's HTTP_OP. Build:
//   emcc fetch_test.c -sFETCH -sEXIT_RUNTIME=0 -o fetch_test.js
// then open fetch_test.html in a browser. It GETs a same-origin file and prints the
// HTTP status + byte count (the exact signals HTTP_OP needs).
#include <emscripten/fetch.h>
#include <stdio.h>
#include <string.h>

static void on_ok(emscripten_fetch_t* f) {
    printf("FETCH OK: status=%d bytes=%llu url=%s\n",
        (int)f->status, (unsigned long long)f->numBytes, f->url);
    printf("first-bytes: %.60s\n", f->data ? f->data : "(none)");
    emscripten_fetch_close(f);
}

static void on_err(emscripten_fetch_t* f) {
    printf("FETCH ERR: status=%d url=%s\n", (int)f->status, f->url);
    emscripten_fetch_close(f);
}

int main(void) {
    emscripten_fetch_attr_t attr;
    emscripten_fetch_attr_init(&attr);
    strcpy(attr.requestMethod, "GET");
    attr.attributes = EMSCRIPTEN_FETCH_LOAD_TO_MEMORY;
    attr.onsuccess = on_ok;
    attr.onerror = on_err;
    printf("starting fetch of fetch_test.html ...\n");
    emscripten_fetch(&attr, "fetch_test.html");   // same-origin (no CORS needed for the de-risk)
    return 0;   // runtime stays alive (EXIT_RUNTIME=0) so the async callback can fire
}
