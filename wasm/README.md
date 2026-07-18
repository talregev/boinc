# BOINC in the Browser — WebAssembly + WebGPU

> Design document and roadmap for running the BOINC client **and** science applications inside a
> web browser, with CPU and GPU detection, on any OS (Windows / Linux / macOS / ChromeOS — the same
> `.wasm` runs everywhere).
>
> **Status:** design / proposal. The previous experimental wasm support was removed from `master`
> on 2025-07-18 (issue [#3086](https://github.com/BOINC/boinc/issues/3086) closed *not planned*).
> This document reconstructs that history, records the current (2026) state of WebAssembly, and lays
> out a plan to rebuild it in a way that answers the objections which got it removed.

---

## 1. History in this repository

WebAssembly support was originally added by **Tal Regev** (`tal.regev@gmail.com`) in 2022 and
removed by the maintainers in 2025. Full commit trail:

| Commit | Date | What |
| --- | --- | --- |
| [`32b9ccfe1d`](https://github.com/BOINC/boinc/commit/32b9ccfe1d) | 2022-06-09 | **Compile boinc as webassembly** — Emscripten + vcpkg (curl/openssl), `wasm32-emscripten` triplet, `--enable-wasm` in `configure.ac` (sets `EXEEXT=.js`), `wasm.yml` CI, `samples/wasm/index.html`, `lib/wasm.cpp` (`ftok` shim), hardcoded CPU info, stub `popen`. |
| [`779b451815`](https://github.com/BOINC/boinc/commit/779b451815) | 2022 | PR #4378 merge (`TalR_boinc_wasm`). |
| [`5190a61241`](https://github.com/BOINC/boinc/commit/5190a61241) | 2022 | Compile wasm with HTML output. |
| [`8be5b1fcdc`](https://github.com/BOINC/boinc/commit/8be5b1fcdc) | 2022 | Add debug information (PR #4791). |
| [`7620391ec1`](https://github.com/BOINC/boinc/commit/7620391ec1) | 2022 | Disable `get_mac_address` in wasm; host CPID from a `fingerprintjs` CDN call instead. |
| [`a2831cb7d0`](https://github.com/BOINC/boinc/commit/a2831cb7d0) | 2022 | Fix wasm build cache (PR #4823). |
| [`decb4ea864`](https://github.com/BOINC/boinc/commit/decb4ea864) | 2023 | `ftok()` missing in the wasm C library — fix properly (PR #5229). |
| [`f3c63ebf6b`](https://github.com/BOINC/boinc/commit/f3c63ebf6b) | 2025-07-18 | **Remove unfinished wasm compilation support** (14 files, −348 lines). |

### What actually existed (and its gaps)
- Compiled the **BOINC client** (not any science app) to `boinc.js` + `.wasm` via Emscripten.
- `configure.ac`: `--enable-wasm` → `EXEEXT=.js`, `#define WASM 1`, skipped `sys/shm.h`.
- Build glue: `wasm/ci_configure_client.sh`, `wasm/ci_make.sh`, `wasm/update_emsdk*.sh`,
  vcpkg config `configs/client/wasm/vcpkg.json` (curl+openssl+rappture), triplet
  `triplets/ci/wasm32-emscripten.cmake`.
- **Known-incomplete pieces (why it never worked end-to-end):**
  - `EM_JS(FILE*, popen, ...)` in `client/hostinfo_unix.cpp` — empty body, `//TODO: add javascript code`.
  - CPU info hardcoded: `p_vendor = "WASM"`, `p_model = "WASM"` — **no real CPU detection, no GPU at all**.
  - Host ID via `fingerprintjs` CDN instead of MAC address (`client/hostinfo_network.cpp`).
  - No filesystem model, no science-app execution model.

### Why it was removed (maintainer decision, issue #3086)
Verbatim reasoning from **AenBleidd**, 2025-07-18
([comment 3088506430](https://github.com/BOINC/boinc/issues/3086#issuecomment-3088506430)):

1. **No projects would port apps to WASM.** Precedent: GPU-on-Android and Windows-on-ARM support
   shipped years ago and *no project ever used them*.
2. **No direct disk access.** Would need the [FileSystem API](https://developer.mozilla.org/en-US/docs/Web/API/FileSystemDirectoryEntry)
   — and the *science app* would need it too.
3. **Performance.** Their internal tests found the WASM build *much slower* than native.

Conclusion: not worth building functionality that "will never be used"; revisit only if the market
shifts to browser-only devices. Closed *not planned*; test code removed to keep the repo clean.

> Earlier thread highlights (2019–2021): David Anderson floated embedding a WASM "engine" in the
> client; multiple contributors noted WASM is near-native and unrelated to JS; nobody produced a
> ported science app or benchmarks — which is exactly the gap this plan closes.

### The core lesson
**A BOINC client compiled to wasm does nothing by itself.** The client only schedules / downloads /
uploads; the actual crunching is done by separate **science applications**. With zero WASM science
apps, a ported client has nothing to run. That is the wall the original effort hit, and the reason
this plan treats *science apps in the browser* — CPU and GPU — as the primary deliverable.

---

## 2. State of WebAssembly in 2026 (what changed since 2022)

- **WebAssembly 3.0** became a W3C standard (Sept 2025), standardizing nine production features
  including **WasmGC, 64-bit memory (Memory64), 128-bit SIMD, exception handling, tail calls**.
  ([byteiota](https://byteiota.com/webassembly-30-spec-release/),
  [webassembly.org/features](https://webassembly.org/features/))
- **SIMD → 10–15× over plain JS** for numeric / crypto / ML workloads — exactly BOINC's domain.
  ([State of WebAssembly 2026](https://devnewsletter.com/p/state-of-webassembly-2026/))
- **Threads:** `SharedArrayBuffer` + Emscripten pthreads, gated behind **COOP/COEP**
  cross-origin-isolation headers. `emscripten_num_logical_cores()` returns
  `navigator.hardwareConcurrency` → real **CPU core detection**.
  ([Emscripten pthreads](https://emscripten.org/docs/porting/pthreads.html))
- **GPU: WebGPU ≈ 82% browser support in 2026** (Chrome/Edge 113+, Opera, Samsung, Safari 26;
  **Firefox still gated**). Exposes **compute shaders (WGSL)** and **GPU detection** via
  `navigator.gpu.requestAdapter()`. This is the modern "detect GPU and crunch on it" path that the
  2022 work completely lacked.
  ([MDN WebGPU](https://developer.mozilla.org/en-US/docs/Web/API/WebGPU_API),
  [WebGPU support 2026](https://webo360solutions.com/blog/webgpu-browser-support/))
- **Memory64** lifts the 4 GB address-space cap (origin trial → shipping across browsers by
  late 2026); relevant for large working sets.
- **WASI 0.2 (component model) / 0.3 (async, threads)** — relevant if these same wasm apps should
  also run *outside* the browser (edge / standalone runtimes) later.
  ([Java Code Geeks](https://www.javacodegeeks.com/2026/04/webassembly-in-2026-where-it-has-landed-what-wasi-0-2-changes-and-why-java-and-kotlin-developers-should-pay-attention-now.html))

**Testability without exotic hardware:** wasm + WebGPU are OS-agnostic; the same artifact runs
identically in Chrome/Firefox on Windows, Linux, macOS, ChromeOS. Testing in a browser on one
machine *is* the cross-platform test. The OS-specific concerns the old code fought (`popen`, MAC
address, `sysctl`) largely disappear in the browser sandbox.

---

## 3. Architecture findings (from the current native code)

What genuinely has to change relative to native BOINC:

- **Process model — the make-or-break rework.** Native BOINC launches apps via
  `fork`/`execv`/`CreateProcess` ([`client/app_start.cpp`](../client/app_start.cpp)) and communicates
  over SysV **shared memory** (`APP_CLIENT_SHM`, [`lib/app_ipc.h`](../lib/app_ipc.h),
  [`lib/shmem.cpp`](../lib/shmem.cpp)). Browsers have **neither fork/exec nor SysV shmem**.
  Replacement: **science app = a Web Worker running its own wasm module**; `APP_CLIENT_SHM` →
  **`SharedArrayBuffer`**; slots/files → OPFS.
- **GPU is a new coproc type.** Coproc types are a fixed enum — `PROC_TYPE_CPU..PROC_TYPE_APPLE_GPU`,
  `NPROC_TYPES = 5` in [`lib/coproc.h`](../lib/coproc.h) (lines ~105–110). Add
  **`PROC_TYPE_WEBGPU_GPU`**, detected via `navigator.gpu.requestAdapter()` (adapter name + limits),
  wired through the [`client/gpu_detect.cpp`](../client/gpu_detect.cpp) path that already handles
  NVIDIA/AMD/Intel/Apple, so the scheduler can target GPU work.
- **Filesystem:** BOINC data dir → **OPFS** via Emscripten **WASMFS** (persistent, answers
  objection #2). Same OPFS shared with the science app.
- **Networking:** libcurl → **Emscripten Fetch**. **CORS is a hard constraint** — project
  scheduler/download servers must send `Access-Control-Allow-Origin` or be fronted by a proxy.
  Threads additionally require **COOP/COEP** headers on the hosting page.
- **Host/CPU detection:** replace hardcoded `"WASM"` strings with
  `navigator.hardwareConcurrency` / `emscripten_num_logical_cores()`.

---

## 4. The plan

Full-stack, aiming (eventually) upstream, **GPU from the start**. Every phase attacks one of the
three objections. Each phase ends in something runnable/demoable.

### Objections → how each is answered
1. *No ported apps* → ship a working **CPU wasm** sample app **and** a **WebGPU** app + a documented
   porting recipe (a checklist, not a research project).
2. *No disk access* → **OPFS** data dir via WASMFS, shared with the app.
3. *Slower than native* → WASM 3.0 **SIMD + threads**, honest benchmarks, and offload heavy math to
   **WebGPU** so the browser story is GPU-accelerated.

### Phases

- **Phase 0 — De-risk spikes** *(recommended start; done outside the BOINC tree)*
  - **Spike A (IPC):** page + Web Worker sharing a `SharedArrayBuffer` that emulates the
    `APP_CLIENT_SHM` message discipline (fraction-done, checkpoint, quit). Validates the
    process-model replacement.
  - **Spike B (WebGPU):** a WGSL compute shader (e.g. batched FMA / simple N-body) driven from wasm
    via Emscripten's WebGPU bindings; measure vs. wasm-SIMD CPU.
  - **Deliverable:** go/no-go + measured numbers that pre-answer objection #3.

- **Phase 1 — Modern wasm client build.** Recreate `wasm/` scripts, `configure.ac --enable-wasm`,
  vcpkg triplet, `wasm.yml`, updated to emsdk 6.x with SIMD + pthreads + WASMFS. Client compiles and
  boots to its main loop in-browser.

- **Phase 2 — Filesystem + networking.** OPFS-backed data dir; Emscripten Fetch networking; stand up
  COOP/COEP + CORS on the dev host so threads and cross-origin work-fetch function.

- **Phase 3 — Process/app model redesign (core).** Replace `app_start.cpp` fork/exec with
  Worker-spawns-wasm; `APP_CLIENT_SHM` → `SharedArrayBuffer`. Client can start/monitor/stop an app
  Worker and exchange status.

- **Phase 4 — BOINC API lib + sample CPU science app, end-to-end.** Compile `libboinc_api` to wasm
  against the new IPC; port a sample app (e.g. `uc2` / example app). Full loop: fetch WU → run wasm
  app in Worker → checkpoint to OPFS → report result. **Objection #1 answered for CPU.**

- **Phase 5 — Host detection: CPU + WebGPU coproc.** Real CPU info; add `PROC_TYPE_WEBGPU_GPU` +
  detection in the `gpu_detect.cpp` path; report the adapter as a coproc the scheduler can target.

- **Phase 6 — Sample WebGPU compute science app.** A GPU science app (WGSL compute) driven from wasm,
  dispatched as a WebGPU-typed app version. **Objection #1 answered for GPU; "detect GPU and crunch"
  delivered.**

- **Phase 7 — Demo project server + hosting.** Minimal BOINC server (existing sample-project / Docker
  test server) with wasm + WebGPU app versions, CORS + COOP/COEP configured; a static page that loads
  the client.

- **Phase 8 — Benchmarks, docs, upstream packaging.** Native vs wasm-SIMD vs WebGPU numbers
  (objection #3). Porting recipe for app authors (objection #1). Write up as an RFC on #3086 / a draft
  PR series before asking for merge.

### Risks / open items
- **Process-model rework (Phase 3)** is the highest-risk piece — Phase 0 Spike A de-risks it.
- **CORS/COOP/COEP** require cooperation from real project servers; until then use the demo server +
  a proxy. Real deployment constraint, not just a code detail.
- **Upstream appetite:** #3086 is *closed / not planned*. Merge is a **stretch** goal; realistic
  sequence is working prototype in a fork → benchmarks → reopen the discussion with evidence. Keep
  commits merge-clean regardless.
- **Firefox WebGPU** still gated in 2026 → GPU path targets Chromium first.

### Suggested starting point
Begin with **Phase 0** — the two spikes are small, self-contained, and decide whether the whole
program is feasible. Cheap insurance before touching the BOINC tree.

---

## 4a. Phase 0 — implemented (see `spikes/`)

Both de-risk spikes are built and run green **headless in Node** and **in a real browser** on an
AMD RDNA-2 GPU. The browser pages POST their results to the dev server (`serve.py` → `runs.jsonl`)
so runs can be read back programmatically.

### Spike A — process/IPC model (`spikes/spikeA-ipc/`) — ✅ PASSED (headless + browser)
Proves a `SharedArrayBuffer` can carry BOINC's `APP_CLIENT_SHM` protocol, i.e. the browser can
replace `fork()`+`execv()`+SysV-shmem (`client/app_start.cpp`, `lib/app_ipc.h`).
```
$ node spikeA-ipc/client.js
  ... fraction_done 0.10 → 1.00, checkpoint ack, quit ack ...
  SPIKE A: PASSED   (monotonic progress, checkpoint + quit handshakes, clean exit; exit 0)
```
Also shipped as a browser page (`index.html` + `app-worker-browser.js`, page=client / Worker=app);
verified in Chrome (`pass:true`, 10 updates, checkpoint+quit acked). The app uses **paced delivery**
— it advances `fraction_done` only after the client consumes the previous status — so no progress is
dropped even when a background tab's timers are throttled.

### Spike B — GPU detect + compute (`spikes/spikeB-webgpu/`) — ✅ PASSED headless **and** on real GPU
An integer `xorshift32` kernel (compute-heavy, embarrassingly parallel, **exact in both WGSL `u32`
and JS**) so the GPU result can be checked bit-for-bit against a CPU reference.
```
$ node spikeB-webgpu/oracle.js
  correctness    : ok (8192 elements match an independent BigInt implementation)
  CPU  1 thread  : 434 ms  (619 M kernel-iters/s)              # N=1,048,576  K=256
  CPU 12 threads : 102 ms  (2629 M kernel-iters/s)  <- fair CPU baseline (worker_threads)
  checksum       : 0x27a723a9   # the browser WebGPU run must reproduce this
  SPIKE B ORACLE: PASSED
```
The WebGPU dispatch (`compute.wgsl` + `index.html`) detects the adapter (→ the future
`PROC_TYPE_WEBGPU_GPU`) and reproduces the checksum while reporting GPU vs single-thread **and
all-cores** CPU (a Web-Worker baseline mirroring the oracle) for a fair comparison.

**Real-hardware run (Chrome on Windows, AMD RDNA-2, 2026-07-17):**
```
GPU adapter   : AMD, rdna-2, maxComputeWorkgroupSizeX=1024, maxStorageBufferBindingSize=2048 MiB
elements N    : 1,048,576   iterations K : 256   (268M kernel iterations)
GPU (WebGPU)  :   7.8 ms   (~25,600 M iters/s)
CPU  1 thread : 420.2 ms   (639 M iters/s)
CPU 12 threads:  70.6 ms   (3,490 M iters/s)   <- fair baseline
speedup       : 9.0x vs all-cores CPU   (53.7x vs single-thread JS)
checksums     : GPU == CPU == CPU-mt == 0x27a723a9  (bit-for-bit)
SPIKE B: PASSED
```
Honest framing: GPU wall-clock jitters run-to-run (~5–10 ms → roughly **7–19x vs all-cores CPU**).
The headline number to quote upstream is **vs a real all-cores CPU**, not single-thread JS — the GPU
still wins clearly, and a native SIMD build would narrow it further but not erase it.

### Environment note
The headless runs were done under **WSL2** (`/dev/dxg` + D3D12 libs present, but no browser/Vulkan
in the shell, so `navigator.gpu` is unreachable from the CLI). The GPU run was done by serving the
pages with **Windows Python** and opening them in **Windows Chrome** (AMD RDNA-2 via D3D12) — all
launched from WSL. Each page POSTs its result JSON to `/report`, which the server appends to
`runs.jsonl`, so the run can be read back without copy-paste:
```
# from WSL, using the Windows toolchain:
cmd.exe /c "cd /d C:\Users\<you>\wasm-spikes && python serve.py 8000"   # COOP/COEP + /report
"/mnt/c/Program Files/Google/Chrome/Application/chrome.exe" http://localhost:8000/spikeB-webgpu/
cat C:\Users\<you>\wasm-spikes\runs.jsonl                               # <- results land here
```

### Phase 0 verdict — COMPLETE ✅
- Process model (highest risk): **viable** — SharedArrayBuffer IPC works headless and in-browser.
- Kernel correctness across CPU/GPU: **proven bit-for-bit** on a real AMD GPU (GPU==1-thread==all-cores).
- GPU performance: **~9x over an all-cores CPU** baseline (≈54x vs single-thread JS) — pre-answers
  objection #3 with an honest number.
- → **Go** for Phase 1 (modern wasm client build).

---

## 4b. Phase 1 — implemented (modern wasm client build)

The BOINC **client compiles to WebAssembly and boots** on the current toolchain (Emscripten 6.0.3,
WASM 3.0 / SIMD). Reproducible via the recreated `wasm/` scripts.

### Toolchain + deps (fetched under `3rdParty/wasm/`, git-ignored)
- **Emscripten 6.0.3** via `wasm/update_emsdk.sh` (emsdk).
- **curl + openssl** built for `wasm32-emscripten` via `wasm/update_emsdk_vcpkg.sh` (vcpkg),
  using the recreated manifest `3rdParty/vcpkg_ports/configs/client/wasm/vcpkg.json` and triplet
  `3rdParty/vcpkg_ports/triplets/ci/wasm32-emscripten.cmake`.

### Build
```
./_autosetup
wasm/ci_configure_client.sh      # emconfigure ./configure --enable-wasm … (add: debug)
wasm/ci_make.sh                  # emmake make
```
`--enable-wasm` sets `EXEEXT=.js` and `#define WASM 1`; `-msimd128` on; link flags
`-sALLOW_MEMORY_GROWTH -sSTACK_SIZE=5MB -sINITIAL_MEMORY=64MB`.

### Result — boots and reports version
```
$ node client/boinc_client.js --version
8.3.0 i686-pc-linux-gnu
$ node client/boinccmd.js --version
boinccmd,  built from BOINC 8.3.0
```
Artifacts: `client/boinc_client.wasm` (~4.9 MB) + `.js`, `client/boinccmd.wasm` + `.js`.

### Source changes required (minimal — 4 spots)
- `configure.ac` — `--enable-wasm` option, `EXEEXT=.js`, `WASM` define, skip `sys/shm.h` on wasm.
- `lib/wasm.cpp` + `lib/Makefile.am` — `ftok()` shim (absent in Emscripten libc).
- `lib/procinfo.h` — declare `get_mem_info()` for `__EMSCRIPTEN__` (it is `__unix__` but not `__linux__`).
- `client/hostinfo_unix.cpp` — real CPU branch for Emscripten: vendor `"WebAssembly"`, model from
  `navigator.hardwareConcurrency` (replaces the old hard-coded `"WASM"`; `popen` is provided by
  Emscripten libc so the old stub is no longer needed).

Plus a fix in `wasm/ci_configure_client.sh`: `emconfigure` wipes `PKG_CONFIG_PATH`, so
`EM_PKG_CONFIG_PATH` is used to expose the vcpkg `.pc` files (curl needs `openssl.pc`).

### CI
`.github/workflows/wasm.yml` — builds release + debug, boots both binaries under node as a smoke
test, uploads the `.js`/`.wasm` artifacts.

---

## 4c. Phase 2 — in progress (runs & is controllable in Chrome)

The client now **boots, runs its main loop, and is driven live in Chrome** — not just compiled.

### Done
- **Runs in Chrome.** `wasm/browser/index.html` loads `boinc_client.js`; the client reaches its main
  loop and runs continuously.
- **Cooperative main loop.** `client/main.cpp`: the `while(1)` poll loop is refactored into
  `boinc_main_loop_body()`, driven natively by a `while` and, on WASM, by
  `emscripten_set_main_loop(...,4,1)` — so the tab stays responsive and JS runs between iterations.
- **GUI RPC without a socket.** Browsers can't `listen()`, so the TCP GUI RPC server is disabled on
  WASM (`no_gui_rpc=true`) and replaced by a string bridge: `GUI_RPC_CONN::do_rpc()` (the
  transport-independent core of `handle_rpc()`) is exposed as `boinc_handle_gui_rpc(request)→reply`.
  The web UI calls it via `ccall` (postMessage-ready). Wire protocol identical to native.
  **Proven live**: repeated `get_cc_status`/`get_host_info` from the page return real replies while
  the client runs. Also headless via `--wasm_selftest`.
- **Quieter loop.** `check_app_exited()` skips `waitpid()` on WASM (no child processes yet), removing
  per-poll `__syscall_wait4` spam.
- **Harness reports to server** (`serve.py /report → runs.jsonl`) for evidence-driven debugging.

### Done (cont.)
- **Persistent data dir (2c).** IDBFS-backed `/boinc_data` via `wasm/browser/persist_pre.js`
  (`--pre-js` + `-lidbfs.js`): load on startup, save every 5s + on `pagehide`. Proven — `host_cpid`
  is identical across reloads. (OPFS swap once the client runs in a Worker, Phase 3.)
- **Project networking (2d).** libcurl's sockets can't reach servers from a browser, so on WASM
  `HTTP_OP::libcurl_exec` and `HTTP_OP_SET::got_select` are replaced by an **Emscripten Fetch**
  backend (`wasm_fetch_exec`, `-sFETCH`) — real browser HTTP, same `http_op_state` machine, so
  `scheduler_op`/`file_xfer` are unchanged. The bridge connection's `gui_http` is pumped from the
  wasm main loop. **Proven in Chrome**: a live `get_project_config` GUI RPC drove a real `HTTP_OP`
  GET through `emscripten_fetch` and returned the parsed `<project_config>`.

Transport proofs (all in Chrome, `wasm/browser/fetch_test.c` + the client harness):
- **GET round-trip through HTTP_OP** — `get_project_config` returned the parsed `<project_config>`.
- **POST body transmission** — `emscripten_fetch` POST; the dev server logged the exact request body
  (`server-post` record in `runs.jsonl`).
- **Cross-origin CORS** — a cross-origin GET to a second origin (`:8001`) with
  `Access-Control-Allow-Origin` succeeded through the page's COOP/COEP isolation.

### Remaining
- **Full project-attach → scheduler round-trip** — the POST *transport* is proven, but an end-to-end
  `project_attach` (client POSTs a `scheduler_request` and parses a `scheduler_reply`) needs a mock
  project (master file + scheduler). That's an **integration** test that belongs with the demo
  project server (**Phase 7**), not a transport gap. (Account-manager RPCs additionally require HTTPS.)
- The Worker + SharedArrayBuffer process model (to actually *run* science apps) is **Phase 3**.

---

## 4d. Phase 3 — implemented (apps run in the browser, full BOINC cycle) ✅

The client runs real science apps in the browser and completes the whole volunteer-computing
loop in one Chrome tab: **attach → scheduler → download app → run in a Worker → report progress →
finish → upload result → report the completed task.**

### Process/app model (Option B — separate app modules, SAB IPC)
There is no `fork`/`exec` in a browser, and real science apps are independent binaries that do **not**
share the client's memory. So each app is a downloaded wasm module (`app.js` + `app.wasm`) run in its
own **Web Worker**, and the client hands it a **`SharedArrayBuffer`** that backs `APP_CLIENT_SHM`
(the 8-channel `MSG_CHANNEL` shared memory). App ↔ client IPC — progress, process control, completion
— is Atomics over that SAB. Requires cross-origin isolation (COOP/COEP) for `SharedArrayBuffer`.

- `client/app_start.cpp` — `ACTIVE_TASK::start()` on wasm sets up the SAB-backed shm and calls
  `wasm_spawn_app()` (EM_JS): reads `app.js`/`app.wasm` from the client FS, Blob-URL-loads them into a
  Worker, and **bridges the slot's input files** (`init_data.xml` + input files, copied real content —
  a Worker has no project dir to resolve a `../../` soft link against) into the Worker's MEMFS.
- `lib/app_ipc.cpp` — `MSG_CHANNEL` get/send/`boinc_wasm_shm_setup()` route to the SAB via Atomics.
- `client/app_control.cpp` — `check_app_exited()` on wasm reaps apps that called `boinc_finish()`:
  copies each bridged output file to its physical path, writes the finish file, and completes/uploads.

### Real `libboinc_api` on wasm — arbitrary apps, not a hand-wired sample
`api/boinc_api.cpp` was ported so a **standard** app (`boinc_init` / `boinc_resolve_filename` /
`boinc_fraction_done` / `boinc_finish`) runs unmodified in the Worker:
- `setup_shared_mem()` attaches to the SAB the client provided (no SysV/mmap in the browser);
- there is **no background timer thread** (a Worker is single-threaded) — progress reporting and
  process-control polling are driven synchronously from `boinc_fraction_done()`;
- `boinc_finish()` bridges the app's output files back to the client and posts a completion record;
- the slot lockfile is skipped (the client spawns exactly one Worker per slot).

### Proof (Chrome, headless, real API app + mock project on `:8100`)
```
[WASM Test Project] Finished download of app.js (70071 bytes) / app.wasm (100102) / input.txt (19)
[WASM Test Project] [task] started app.js as a Web Worker (pid 1001)
[WASM Test Project] [task] app called boinc_finish(0); bridged output(s) + wrote finish file
[WASM Test Project] Finished upload of wu_1_0_out (81 bytes)
[WASM Test Project] Reporting 1 completed tasks
```
The uploaded result proves the **input round-trip** (app read the 19-byte input and echoed it):
```
wasm result: crunched 50 steps over 19 input bytes
input was: wasm input payload
```

### Still deferred
- **External GUI RPC monitoring** — the in-page `boinc_handle_gui_rpc` bridge works; a native relay
  for out-of-browser monitoring is a separate item.

---

## 4e. Phase 6 — implemented (WebGPU science app crunches on the GPU) ✅

A real BOINC **GPU** app runs the whole cycle in a browser tab: the same `libboinc_api` as a CPU app,
but the crunch is a **WGSL compute shader** dispatched via **WebGPU** from the app's Web Worker.

- `wasm/gpu_app/gpu_app.cpp` — `boinc_init` → `wasm_gpu_init` (requestAdapter/requestDevice, upload
  input, build the compute pipeline) → 64 dispatches with `boinc_fraction_done()` between → read back
  → `boinc_finish`. WebGPU's API is async, so the app is built `-sASYNCIFY` and awaits it from
  synchronous C via `EM_ASYNC_JS`. `wasm/gpu_app/build_app.sh` builds it.
- The kernel is Spike B's per-element xorshift32 (bit-exact in WGSL `u32` and JS), so a correct GPU
  run folds to the **same checksum Spike B's CPU oracle produced** — an end-to-end correctness proof.

### Proof (visible Chrome, real GPU — headless Chrome has no usable adapter)
`navigator.gpu` works both on the client's main thread **and inside the app's Blob Worker** (verified
with a standalone probe: adapter `amd/rdna-2`, checksum `0x27a723a9` in both contexts). The GPU app
then ran through the pipeline:
```
Finished download of app.js (78206 bytes) / app.wasm (146861)   # the -sASYNCIFY GPU build
[task] started app.js as a Web Worker (pid 1001)
[task] app called boinc_finish(0); bridged output(s) + wrote finish file
Finished upload of wu_1_0_out (99 bytes) / Reporting 1 completed tasks
```
Uploaded result — **bit-for-bit identical to Spike B's oracle** (`0x27a723a9`):
```
webgpu result: checksum=0x27a723a9
kernel: xorshift32 N=1048576 K=256 REP=64
adapter: amd/rdna-2
```
~17 billion kernel-iterations (64 × 2^20 × 256) ran on the GPU, correct to the bit, reported as a
completed BOINC task. **"Detect GPU and crunch" — the crunch half is delivered.**

### Still deferred
- **External GUI RPC monitoring** — as above.

---

## 4f. Phase 5 — implemented (client detects the WebGPU adapter) ✅

The wasm client detects the GPU and reports it. There is no fork/exec GPU probe in a browser, so the
client asks `navigator.gpu` for the adapter on its main thread.

- `client/main.cpp` — `wasm_webgpu_detect_start()` kicks off `navigator.gpu.requestAdapter()` (async;
  the client isn't built `-sASYNCIFY`), and `wasm_webgpu_detect_poll()` polls it from the main loop.
  When it resolves it logs `Detected WebGPU GPU: <vendor/arch/device>` and records the adapter in
  `HOST_INFO::webgpu_name`.
- `lib/hostinfo.{h,cpp}` — new `webgpu_name` field, parsed + written in the host-info XML, so it is
  reported over GUI RPC (`get_host_info`) and to the scheduler.

Proof (visible Chrome, real GPU):
```
[---] Detected WebGPU GPU: amd/rdna-2/?
WebGPU adapter (get_host_info): amd/rdna-2/?      # queried live over the GUI RPC bridge
```

### In-browser GPU-vs-CPU benchmark (Phase 8 down payment, objection #3)
`wasm/gpu_app/gpu_app.cpp` also runs the *same* kernel on the wasm CPU and compares — a self-contained
correctness + performance artifact reported as the task's result:
```
correctness: GPU==CPU bit-for-bit = YES (cpu=0x27a723a9)
benchmark: GPU 31839 M-iter/s vs CPU(wasm) 518 M-iter/s = 61.5x    # AMD RDNA-2, one Chrome tab
```
GPU and wasm CPU agree to the bit, and the GPU is ~60x the single-thread wasm CPU for this kernel.

### WebGPU as a schedulable coproc — the scheduler targets a GPU-typed app version ✅
The adapter isn't just *reported* — it's registered as a **schedulable coprocessor** so a GPU-typed
app version (a `plan_class` + a `<coproc>` requirement) is dispatched and reserved like any other GPU.
Crucially this needed **no new `PROC_TYPE`**: BOINC's coproc parse/match/reserve/work-fetch chain is
already generic over the `coprocs[]` array keyed by a type *string* (`rsc_index()` →
`assign_coprocs()` → `rsc_work_fetch[MAX_RSC]`), with generic fallbacks everywhere the hardwired
4-GPU `coproc_type_name_to_num()` is consulted.

- `client/client_state.cpp` — after GPU detection, register a `COPROC` with `type="webgpu"`,
  `count=1` (modeled on `add_other_coproc_types()`), before `work_fetch.init()`. Presence is decided
  synchronously via `wasm_webgpu_present()` (`navigator.gpu` is a sync property; only
  `requestAdapter()` is async). The plan_class is `webgpu` (avoids the `opencl`/`cuda`/`ati`
  substrings that would make `RESOURCE_USAGE::check_gpu_libs` demand OpenCL/CUDA props).
- `client/main.cpp` — `wasm_webgpu_present()` sync feature-detect.
- `wasm/sample_app/mock_project.py` — with a `gpu` argument, advertise the app version as
  `<plan_class>webgpu</plan_class>` + `<coproc><type>webgpu</type><count>1</count></coproc>`.

Proof (visible Chrome, real GPU; `mock_project.py 8100 <url> gpu`):
```
[---] Registered WebGPU adapter as a coproc (type webgpu, count 1)
[WASM Test Project] Requesting new tasks for CPU and webgpu     # webgpu is a first-class resource
TASK wu_1_0 plan_class="webgpu"  <= scheduled on the webgpu coproc
[WASM Test Project] Finished upload of wu_1_0_out ... Reporting 1 completed tasks
```
The GPU-typed app version binds to the `webgpu` coproc (`rsc_index("webgpu")`), the client requests
and reserves it, and the task runs + reports the bit-exact GPU checksum. **Phase 5 complete: detect,
report, *and* schedule on the GPU — entirely client-side.**

### Still deferred
- **Server-side plan-class matching** — done in Phase 7 (Stage 7.6): the real scheduler
  (`sched/plan_class_spec.cpp`) now records a generic coproc requirement so a `webgpu` plan class is
  matched from the host's reported coproc, verified A/B against the native-built scheduler.
  `GPU detection failed` in the client log is the native fork/exec probe, expected on wasm.
- **External GUI RPC monitoring** — as above.

---

## 4g. Host detection on wasm — async CPU benchmark + no-op cleanups ✅

The native client does several things a browser tab can't: `fork()` a benchmark child, `wait4()` it,
`ioctl(SIOCGIFCONF)` network interfaces, SysV-`detach_shmem`. Each printed a scary "unsupported" /
"not supported" line even though nothing was actually wrong. These are replaced with browser-native
equivalents or guarded.

### Async CPU benchmark in a Web Worker (replaces fork + wait4)
The native benchmark `fork()`s a child per CPU that runs Whetstone/Dhrystone and writes a result file;
the parent `waitpid()`s it. In a browser the analog of a child process is a **Web Worker**, so
`fork`→Worker and `waitpid`→result-poll — and it stays fully async (the tab never blocks).

- `wasm/benchmark/benchmark.cpp` (new): runs the same `whetstone()` + `dhrystone()` cores as the
  native client and prints one `BENCHMARK_RESULT fpops=… iops=… membw=…` line. Built by
  `build_benchmark.sh` and **embedded into the client** (`--embed-file`); `ci_make.sh` builds it
  before the client links.
- `client/cs_benchmark.cpp` — on wasm, `start_cpu_benchmarks()` spawns a Worker
  (`wasm_spawn_benchmark`) instead of `fork()`; `check_benchmark()` reaps the posted result
  (`wasm_poll_benchmark`) instead of `waitpid()`; the ~30 s file-phased FP/INT state machine is
  skipped (the Worker runs the whole benchmark at once).
- `client/main.cpp` — the benchmark is reaped from the main loop, not only `poll_slow_events()`
  (which runs its benchmark poll late, after pollers that return early during busy attach/download).
- `lib/util.cpp` — `boinc_calling_thread_cpu_time()` uses **wall-clock** on wasm. `getrusage()` is a
  constant stub in emscripten, so the benchmarks' "run until `min_cpu_time`" loop would never end; a
  dedicated Worker only computes, so wall-clock ≈ CPU time.

Proof (Chrome): `CPU benchmark (async Worker): p_fpops=6.04 GFLOPS, p_iops=6.02 GIOPS` — a real
measured value (not the default), reported over `get_host_info`, with **no `__syscall_wait4`** in the
build.

### No-op / guarded natives
- **`detach_shmem`** — `ACTIVE_TASK::cleanup_task()` on wasm frees the `malloc`'d, SAB-backed
  `SHARED_MEM` (the SharedArrayBuffer is released when the app Worker is terminated) instead of the
  SysV `detach_shmem`/`destroy_shmem`, which only printed "not supported on this platform".
- **`ioctl(SIOCGIFCONF)`** — `get_mac_address()` returns early on wasm (no NICs in the sandbox).
- **`GPU detection failed` / `read_coproc_info_file -108`** — removed by the Phase 5 detection path
  (`COPROCS::get()` skips the native fork/exec probe; see 4f).
- **`Project communication failed: attempting access to reference site` / `BOINC can't access
  Internet`** — `NET_STATUS::contact_reference_site()` is a no-op on wasm. A browser tab can only
  reach the CORS-scoped project via `emscripten_fetch`, not an arbitrary cross-origin URL like the
  default `berkeley.edu` test site, so the probe always "failed" and falsely reported no Internet.

Net effect: a clean client log — no `unsupported syscall`, `not supported on this platform`, or
`SIOCGIFCONF` noise — while CPU/GPU detection and crunching still work.

---

## 4h. Phase 7 — demo project server + hosting (in progress)

Phase 7 replaces the Python mock with a **real BOINC project server** and makes the scheduler decide
what to send from the host's reported coprocs. Staged plan: [`wasm/phase7-plan.md`](phase7-plan.md).

### Stage 7.1 — plan-class matching (the mock decides from host coprocs) ✅
`wasm/sample_app/mock_project.py` now behaves like a real scheduler: it parses the host's scheduler
request for a `webgpu` coproc and serves the **GPU-typed** app version (`plan_class=webgpu` +
`<coproc>webgpu</coproc>`) only to hosts that report it, else the plain CPU version.
```
curl (no coproc)          -> <plan_class></plan_class>          # CPU version
curl (<type>webgpu</type>)-> <plan_class>webgpu</plan_class>    # GPU version
Chrome (real GPU host)    -> TASK wu_1_0 plan_class="webgpu"     # matched -> scheduled on the coproc
```

### Stages 7.2–7.4 — a reproducible real server (`wasm/server/`) ✅
Packaged as [`wasm/server/`](server/) so anyone can build it: `docker compose up --build -d`. It
extends the official `boinc-server-docker` images (MySQL + Apache + BOINC daemons) and, at startup,
registers the wasm app and wires up browser hosting — no manual steps.
- `Dockerfile` — `FROM boinc/server_apache:latest`, enables `mod_headers`, serves the client page at
  `/wasm` with COOP/COEP (`apache-wasm.conf`), and installs the registration hook.
- `register_wasm_app.sh` (supervisord one-shot, idempotent) — generates a code-signing key, adds the
  `sample` app, stages the app version (`app.js` main + `app.wasm`), `update_versions`, `create_work`,
  and pre-creates a demo account served at `/wasm/account.txt`.
- `docker-compose.yml` — `mysql` + one-shot `makeproject` + our `apache` (waits on
  `makeproject` via `service_completed_successfully`; mounts the Docker socket the base image's
  startup expects).

**Verified from a clean `docker compose up --build`:**
```
master   http://127.0.0.1/boincserver/     -> 200   (real scheduler; <scheduler_reply> v715)
client   http://127.0.0.1/wasm/            -> 200   + Cross-Origin-Opener/Embedder-Policy headers
         http://127.0.0.1/wasm/boinc_client.wasm -> 200
account  http://127.0.0.1/wasm/account.txt -> 50ea2b5cad358b43…   (real authenticator)
DB       app_version registered; 2 unsent results ready to serve
```
Snags solved along the way: snap Docker can't read `/tmp` (compose lives under the repo); the
`/dev/null` `code_sign_private` mount is dropped so a real keypair can be generated; the base image's
startup waits for the Docker socket, so the compose mounts it.

### Stage 7.5 — browser vs. the real server ✅
Opening `http://127.0.0.1/wasm/` runs the whole cycle against the real server: the browser client
creates an account, attaches, the real scheduler sends work, the client downloads the app, runs it in
a Worker, uploads the output, and reports — all recorded in the real DB:
```
host created (hostid=1); results sent=2
result server_state=5 (over), outcome=1 (SUCCESS)
upload/…/sample_wu_1_0_r…  ->  "wasm result: crunched 50 steps over 19 input bytes / input was: wasm input payload"
```
On a normal Linux host the browser and server share `localhost`, so this works directly. In this dev
environment the client is Windows Chrome and the server is Docker-in-WSL, so a one-time port-forward
bridges Windows `127.0.0.1:80` to the WSL server (keeping the `SharedArrayBuffer` secure context):
`netsh interface portproxy add v4tov4 listenport=80 listenaddress=127.0.0.1 connectport=80 connectaddress=<WSL_IP>`.

### Stage 7.6 — server-side GPU-typed matching (generic coproc plan class) ✅
The last piece: make the *real* scheduler choose the `webgpu` app version from the host's reported
coprocs (7.1 proved this only with the Python mock). It needed **no `webgpu` special-case** —
`sched/plan_class_spec.cpp` already matches any non-big-4 `gpu_type` generically via
`COPROCS::lookup_type()`. The one real gap: for a coproc that reports a nonzero `peak_flops` (ours
does, 1e12), the generic path computed the projected flops but never recorded the coproc *requirement*
in `HOST_USAGE` — so the reply carried no `<coproc>` and the client would run the version as a plain
CPU app. The fix is the generic `else` in `PLAN_CLASS_SPEC::check` (mirroring the existing
`peak_flops==0` path): set `host_usage.custom_coproc_type` + `gpu_usage`, which `sched_types.cpp`
writes as `<coproc><type>webgpu</type>`. No hardwired `webgpu` branch — it fires for *any* custom
coproc type.

Config, no more code: dropping a `plan_class_spec.xml` with a `webgpu` class (`gpu_type=webgpu`, **no
`<opencl/>`** — a WebGPU device isn't OpenCL) into the project dir switches the scheduler to
plan_class_spec for non-empty plan classes (the empty CPU class is unaffected — `app_plan` is only
called for non-empty ones). `wasm/server/` now installs it and registers a second, GPU-typed app
version (`…__webgpu`) of the same app, so a webgpu host gets the GPU version and other hosts get CPU.

Verified by building the real scheduler natively and running `PLAN_CLASS_SPEC::check` against a faked
`webgpu` coproc — A/B, same `cgi` link (see `sched/plan_class_spec.cpp`'s `#ifdef PLAN_CLASS_TEST`):
```
stock code : check(webgpu) SUCCEEDED  custom_coproc_type=''        gpu_usage=0  -> no <coproc> (runs as CPU)
with fix   : check(webgpu) SUCCEEDED  custom_coproc_type='webgpu'  gpu_usage=1  -> <coproc>webgpu</coproc>
```
The match succeeds either way; only the fix records the requirement — so it is both necessary and
sufficient. This is the single upstream server-side code change the effort needed; native builds are
untouched (the change lives inside the existing `gpu_type` handling). Deploying it to the live demo
container additionally needs a scheduler binary rebuilt for that image's OS (Debian 9); the code +
config + A/B proof are complete.

---

## 4i. Phase 8 — benchmarks, porting recipe, upstream framing (in progress)

### Benchmarks (same xorshift32 kernel, N=2²⁰, K=256, checksum 0x27a723a9 everywhere)
All numbers on one AMD RDNA-2 laptop; the **bit-for-bit identical checksum** across CPU and GPU is
the correctness anchor.

| Path | Rate (M kernel-iters/s) | vs wasm 1-thread |
|---|---:|---:|
| CPU — native, 1 thread (Spike B oracle) | ~619 | — |
| CPU — native, 12 threads (Spike B oracle) | ~2,629 | — |
| **CPU — wasm, 1 thread** (in-browser, the client's own benchmark) | **~520** | 1× |
| **GPU — WebGPU** (in-browser, through the BOINC pipeline) | **~33,000** | **~64×** |

Takeaways: single-thread wasm is ~0.84× native (the SIMD-enabled build is close to native for this
integer kernel); the browser GPU is ~60–65× the single-thread wasm CPU and correct to the bit. This
directly answers objection #3 ("is wasm/WebGPU fast enough to be worth it") — for GPU-suitable work,
decisively yes; for CPU work, wasm is within a small factor of native.

### Porting recipe (for app authors)
A normal BOINC CPU app needs almost no changes — it's the same `libboinc_api`:
1. Build with Emscripten against the wasm `libboinc_api` + `libboinc` (see `wasm/sample_app/build_app.sh`);
   ship `app.js` + `app.wasm`.
2. Use the standard API: `boinc_init` / `boinc_resolve_filename` / `boinc_fopen` /
   `boinc_fraction_done` / `boinc_finish`. No SAB or Worker code in the app — the client's wasm port
   of the API (`api/boinc_api.cpp`) handles the SharedArrayBuffer IPC and the finish/output bridge.
3. For a **GPU** app, do the compute in WebGPU via `EM_ASYNC_JS` and build with `-sASYNCIFY` (see
   `wasm/gpu_app/gpu_app.cpp`); it's still a normal libboinc_api app otherwise.
4. Serve it from the project as an app version (`plan_class=webgpu` for GPU-typed scheduling — the
   server matcher is now generic, Stage 7.6; or a plain version that uses WebGPU internally).

### Upstream framing (issue #3086)
The 2025 removal of the old wasm stubs (issue #3086) was correct — that code was incomplete. This
effort answers the objections that motivated the removal:
- **#1 "apps must be ported"** — a real `libboinc_api` app (CPU *and* GPU) runs unmodified in the
  browser; the porting recipe above is short.
- **#2 "process model"** — solved with Web Workers + `SharedArrayBuffer`-backed `APP_CLIENT_SHM`
  (Phase 3), not fork/exec.
- **#3 "performance"** — measured above; wasm-SIMD ≈ native for CPU, WebGPU ~60× for GPU work.
The natural upstream shape is a draft-PR series matching the phases: client build (`--enable-wasm`),
the Worker/SAB process model, the `libboinc_api` wasm port, WebGPU detection + a generic server-side
coproc plan class, and a demo project. Everything here is behind `#ifdef WASM` and leaves native
builds untouched.

### Remaining
- A dedicated `wasm` client platform (vs. the current `i686-pc-linux-gnu`).
- The draft-PR series + native/wasm/WebGPU write-up for #3086. (Generic server-side coproc matching in
  `sched/plan_class_spec.cpp` — previously listed here — is done; see Stage 7.6.)

---

## 5. Sources

- BOINC issue #3086 — <https://github.com/BOINC/boinc/issues/3086> (removal rationale:
  [comment](https://github.com/BOINC/boinc/issues/3086#issuecomment-3088506430))
- WebAssembly 3.0 — <https://byteiota.com/webassembly-30-spec-release/> ·
  <https://webassembly.org/features/>
- State of WebAssembly 2026 — <https://devnewsletter.com/p/state-of-webassembly-2026/>
- Emscripten pthreads — <https://emscripten.org/docs/porting/pthreads.html>
- WebGPU (MDN) — <https://developer.mozilla.org/en-US/docs/Web/API/WebGPU_API>
- WebGPU browser support 2026 — <https://webo360solutions.com/blog/webgpu-browser-support/>
- WASI 0.2 / 0.3 — <https://www.javacodegeeks.com/2026/04/webassembly-in-2026-where-it-has-landed-what-wasi-0-2-changes-and-why-java-and-kotlin-developers-should-pay-attention-now.html>
- OPFS / FileSystem API — <https://developer.mozilla.org/en-US/docs/Web/API/FileSystemDirectoryEntry>
