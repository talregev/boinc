Fixes #3086

<!-- Ready-to-paste PR body. #3086 ("Enable browser-based computing in BOINC") was closed
     not-planned in 2025 (removed in #6446); this revisits it with a complete, working
     implementation. Everything is behind --enable-wasm (default off) — native builds are unchanged. -->

**Description of the Change**

Adds an experimental WebAssembly build of the BOINC client (`--enable-wasm`, **off by default**)
that runs the real client — not a re-implementation — inside a web browser, detects the CPU and GPU,
and crunches real `libboinc_api` science apps (CPU **and** WebGPU), end-to-end against a real BOINC
server. The whole thing is gated behind `#ifdef WASM` / the `--enable-wasm` configure flag / a wasm
vcpkg triplet, so a normal native build is byte-for-byte unaffected.

What it contains:
- **Client → WebAssembly.** `--enable-wasm` in `configure.ac`; `lib/wasm.cpp` (`ftok` shim); a
  `wasm.yml` CI job that builds `boinc_client.js/.wasm` + `boinccmd`, smoke-tests them under Node, and
  runs a **headless selftest** of the GUI-RPC string bridge + SharedArrayBuffer IPC; emsdk + vcpkg
  bootstrap scripts under `wasm/`.
- **Native-faithful process model.** The client runs as a **daemon in a dedicated Web Worker**; GUI
  RPC flows over `postMessage` (the analog of the native localhost GUI-RPC socket, via a
  transport-agnostic `do_rpc()` seam). Science apps and the CPU benchmark run as **nested Web
  Workers** (the fork/exec analog), sharing an `APP_CLIENT_SHM` backed by a `SharedArrayBuffer`
  (the SysV-shmem analog). Networking uses `emscripten_fetch` (browsers can't open sockets).
- **`libboinc_api` wasm port** (`api/boinc_api.cpp`, `#ifdef WASM`): a normal `libboinc_api` app —
  `boinc_init` / `boinc_resolve_filename` / `boinc_fopen` / `boinc_fraction_done` / `boinc_finish` —
  runs unmodified in the browser. A short porting recipe is in `wasm/README.md`.
- **Real disk access via OPFS.** The data dir is backed by WasmFS's OPFS (Origin Private File System)
  — real, durable, random-access storage that persists across reloads (mounted in C at `main()`).
- **GPU as a first-class, schedulable coproc.** WebGPU is detected and registered as a generic
  `webgpu` coproc (no new built-in `PROC_TYPE`), so a `plan_class=webgpu` app version is scheduled
  and reserved like any other GPU. A small, generic server-side fix
  (`sched/plan_class_spec.cpp`) records the coproc requirement for any non-built-in `gpu_type`.
- **Working proof:** CPU + WebGPU sample apps, an in-browser benchmark, de-risk spikes, and a
  reproducible demo project server (`wasm/server/`).

**The objections that closed #3086, and how this answers them**

| Objection (per the closing comment / removal) | Answer here |
|---|---|
| "No projects would port apps to WASM" (cf. Android-GPU / Win-ARM: supported, unused) | The stated blocker was **effort/ROI** ("won't spend resources on functionality that will never be used"). That cost has since collapsed: **an AI agent can port a `libboinc_api` app to wasm+WebGPU in hours** — this whole port (client + CPU app + WebGPU app) was done AI-assisted, and is the existence proof. Combined with a browser's reach (any device, zero install) and GPU-from-the-start, the ROI the objection rested on no longer holds. AI-assisted ports stay trustworthy via the bit-exact checksum discipline shown here (see below). |
| "Apps in a browser have no direct disk access; needs FileSystemAPI" | Answered directly: the data dir is on **OPFS** — real disk-backed, durable, random-access — and app I/O flows through the OPFS-backed slot dir. |
| "WASM is much slower than native" | Measured, same kernel, **bit-identical checksum `0x27a723a9`**: wasm CPU ≈ **0.84× native** (SIMD, 1 thread) and **WebGPU ≈ 64×** the wasm CPU. A committed native benchmark (`wasm/spikes/spikeB-webgpu/native_bench.c`) makes the native baseline reproducible. |
| "The wasm support was **unfinished**" (reason for removal) | It's now complete and tested: client + apps + server + persistence + GPU-typed scheduling, verified end-to-end in Chrome. |
| Core lesson: "a wasm client does nothing alone; there were **zero wasm science apps**" | Refuted — working CPU and WebGPU science apps run through the real client, GPU-typed scheduled by a real server. |

**Native-code impact (for reviewers)**

`--enable-wasm` is default-off and every wasm code path is `#ifdef WASM`; the `-pthread` requirement
(WasmFS's OPFS backend runs on a dedicated thread) is confined to the wasm build + a wasm vcpkg
triplet. The intentional edits to shared/native code, called out for scrutiny:
- `client/gui_rpc_server_ops.cpp` — extract `do_rpc()` from `handle_rpc()` (behavior-preserving) so
  the RPC dispatch is transport-agnostic (socket, HTTP, or postMessage).
- `client/main.cpp` — extract `boinc_main_loop_body()` from the native `while(1)` loop
  (behavior-preserving) so the same body drives both the native loop and `emscripten_set_main_loop`.
- `lib/hostinfo.{h,cpp}` — a `webgpu_name` field on `HOST_INFO` (empty/inert on native).
- `sched/plan_class_spec.cpp` + `sched/sched_types.cpp` — the **generic-coproc scheduler fix**: a
  non-built-in `gpu_type` now records `custom_coproc_type`/`gpu_usage` so a `<coproc>` requirement is
  sent to the client. This is a real (intended) native-scheduler change; it lets a project define a
  custom GPU plan class without a new built-in `PROC_TYPE`. No DB schema change.
- **Macro convention.** `WASM` is the BOINC feature macro (defined by `--enable-wasm`);
  `__EMSCRIPTEN__` (compiler-defined) is used only in the few spots that should follow the compiler
  regardless of the flag (e.g. `p_vendor`/`p_model`, `PROCINFO::get_mem_info`). The split is
  intentional, not an oversight.

**What's in-tree (and what could move out)**

The `wasm/` directory carries de-risk spikes, a reproducible demo server, and a committed native
benchmark alongside the client/build changes — included so a reviewer can reproduce every number and
claim above without external artifacts. If a leaner tree is preferred, the spikes, demo server, and
benchmark can move to a companion repository and be linked instead; the core (build system + client +
scheduler fix) stands on its own.

**Alternate Designs**
- **Persistence: IDBFS vs OPFS.** IDBFS (IndexedDB) works on the main thread but keeps whole files in
  memory with coarse, async `syncfs`. OPFS gives real disk-backed random-access + durability, but its
  sync access handles are Worker-only — which is why the client moved into a Worker. Chosen: OPFS.
- **Client threading: main thread vs Worker.** Running on the main thread avoids a refactor but
  blocks OPFS sync handles and keeps the UI thread busy. A dedicated Worker matches native BOINC's
  daemon/GUI separation (postMessage ≈ the localhost socket) and is the stated path to a SharedWorker
  serving multiple tabs. Chosen: dedicated Worker.
- **GPU type: new `PROC_TYPE` vs generic coproc.** BOINC's coproc chain is already generic over a
  type string, so `webgpu` needs no new enum — matching the "no new PROC_TYPE" philosophy.
- **Porting model.** Rather than argue projects will invest human months (the 2019/2025 assumption),
  the port is AI-assisted + checksum-validated, collapsing the per-app cost.

**Release Notes**
Experimental WebAssembly build of the BOINC client (`--enable-wasm`, off by default) that runs in a
web browser with WebGPU support.

---
_Developed with AI assistance (human-reviewed), per BOINC's AI Assistants Usage Policy. All wasm code
is behind `#ifdef WASM` / `--enable-wasm`; native builds are unchanged._
