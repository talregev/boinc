// Phase 2d de-risk / transport proof for the emscripten_fetch backend (client/http_curl.cpp).
// The GET round-trip through HTTP_OP is already proven end-to-end in the client; this covers the
// two things the POST path and cross-origin use add on top:
//   (1) POST transmits a request body   (wasm_fetch_exec's is_post branch),
//   (2) a cross-origin request with CORS (Access-Control-Allow-Origin) succeeds.
// Build: emcc fetch_test.c -sFETCH -sEXIT_RUNTIME=0 -o fetch_test.js ; open fetch_test.html.
#include <emscripten/fetch.h>
#include <stdio.h>
#include <string.h>

static void on_get(emscripten_fetch_t* f) {
    printf("SAME-ORIGIN GET: status=%d bytes=%llu\n", (int)f->status, (unsigned long long)f->numBytes);
    emscripten_fetch_close(f);
}
static void on_post(emscripten_fetch_t* f) {
    printf("POST: status=%d (server logs the received body) reply=%.40s\n", (int)f->status, f->data ? f->data : "");
    emscripten_fetch_close(f);
}
static void on_cors(emscripten_fetch_t* f) {
    printf("CROSS-ORIGIN GET (:8001): status=%d bytes=%llu  <- CORS ok if status=200\n",
        (int)f->status, (unsigned long long)f->numBytes);
    emscripten_fetch_close(f);
}

static void start(const char* method, const char* url, const char* body,
                  void (*cb)(emscripten_fetch_t*)) {
    emscripten_fetch_attr_t a;
    emscripten_fetch_attr_init(&a);
    strcpy(a.requestMethod, method);
    a.attributes = EMSCRIPTEN_FETCH_LOAD_TO_MEMORY;
    a.onsuccess = cb; a.onerror = cb;
    if (body) { a.requestData = body; a.requestDataSize = strlen(body); }
    emscripten_fetch(&a, url);
}

int main(void) {
    printf("fetch de-risk: GET, POST(body), cross-origin GET ...\n");
    start("GET",  "fetch_test.html", NULL, on_get);
    start("POST", "http://localhost:8000/post_echo",
          "<acct_mgr_request>proof_of_post_body</acct_mgr_request>", on_post);
    start("GET",  "http://localhost:8001/fetch_test.html", NULL, on_cors);
    return 0;   // EXIT_RUNTIME=0: stay alive for the async callbacks
}
