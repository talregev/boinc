// Spike C — validate WasmFS+OPFS + pthread + FETCH + nested Worker + WebGPU + --embed-file,
// all running OFF the browser main thread (via -sPROXY_TO_PTHREAD, so main() runs on a pthread
// = a Web Worker context, where OPFS sync access handles are legal). This de-risks the client
// -> Worker + IDBFS->OPFS migration before touching any client code.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <emscripten.h>
#include <emscripten/console.h>
#include <emscripten/wasmfs.h>
#include <emscripten/fetch.h>

EM_JS(int, has_webgpu, (), {
  return (typeof navigator !== 'undefined' && navigator.gpu) ? 1 : 0;
});

EM_JS(int, spawn_nested_worker, (), {
  try {
    var code = "self.onmessage=function(e){postMessage((e.data|0)*2);};";
    var w = new Worker(URL.createObjectURL(new Blob([code], {type:'text/javascript'})));
    w.postMessage(21);           // fire-and-forget; proves nested Worker construction in this ctx
    return 1;
  } catch (e) { return 0; }
});

static int read_embed(char* out, int n) {
  FILE* f = fopen("/embed.txt", "r");
  if (!f) return -1;
  int r = (int)fread(out, 1, n - 1, f);
  out[r > 0 ? r : 0] = 0;
  fclose(f);
  return r;
}

static void report(const char* body) {
  emscripten_fetch_attr_t a;
  emscripten_fetch_attr_init(&a);
  strcpy(a.requestMethod, "POST");
  a.attributes = EMSCRIPTEN_FETCH_LOAD_TO_MEMORY | EMSCRIPTEN_FETCH_SYNCHRONOUS;
  a.requestData = body;
  a.requestDataSize = strlen(body);
  emscripten_fetch(&a, "/report");     // also proves emscripten_fetch works off-main-thread
}

int main(void) {
  char res[1024];

  // 1) OPFS mount (must be off main thread) + persistence across reloads via a counter file
  backend_t opfs = wasmfs_create_opfs_backend();
  int mount_rc = wasmfs_create_directory("/data", 0777, opfs);
  int counter = 0;
  int fd = open("/data/counter.txt", O_RDWR);
  if (fd >= 0) { char c[32] = {0}; if (read(fd, c, 31) > 0) counter = atoi(c); close(fd); }
  counter++;
  fd = open("/data/counter.txt", O_RDWR | O_CREAT | O_TRUNC, 0777);
  int wrote_rc = -1;
  if (fd >= 0) { char c[32]; int n = snprintf(c, sizeof c, "%d", counter); wrote_rc = (int)write(fd, c, n); close(fd); }

  // 2) --embed-file under WASMFS
  char emb[64] = {0};
  int emb_rc = read_embed(emb, sizeof emb);

  // 3) nested Worker + WebGPU in this (worker) context
  int nested = spawn_nested_worker();
  int gpu = has_webgpu();

  snprintf(res, sizeof res,
    "{\"opfs_mount_rc\":%d,\"counter\":%d,\"wrote_rc\":%d,\"embed\":\"%s\",\"embed_rc\":%d,\"nested_worker\":%d,\"webgpu\":%d}",
    mount_rc, counter, wrote_rc, emb, emb_rc, nested, gpu);
  emscripten_console_log(res);
  report(res);
  return 0;
}
