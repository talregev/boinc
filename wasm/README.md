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
