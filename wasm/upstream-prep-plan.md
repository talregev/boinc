# Plan — server reproducibility, dedicated `wasm` platform, native benchmark

## Context
The browser-BOINC effort is functionally complete and proven end-to-end (client wasm port,
CPU + GPU apps via real `libboinc_api`, client- **and** server-side generic-coproc scheduling, a
live demo where a from-source BOINC v8.3.0 server dispatched `plan_class=webgpu` tasks to a browser
that crunched them on a real GPU, bit-exact `0x27a723a9`, 11/11 SUCCESS).

Three follow-ups harden it for upstreaming (#3086) and reproducibility. They do **not** add new
capability — they close self-consistency gaps found during the demo:

1. **Server reproducibility.** `wasm/server` does `FROM boinc/server_apache:latest` and pulls
   `boinc/server_{mysql,makeproject}:latest-defaultargs` — the **prebuilt Docker Hub images (BOINC
   v7.15), which lack the generic-coproc fix**. The scheduler binaries come from the `makeproject`
   image (it compiles `sched/`). So a clean-clone `docker compose up` would dispatch the webgpu app
   version with **no `<coproc>`** — the exact bug the fix addresses. The demo only worked because
   base images were built from source locally this session.
3. **Dedicated `wasm` platform.** The wasm client reports `i686-pc-linux-gnu` (the native build's
   `HOSTTYPE`) because `client/cs_platforms.cpp::detect_platforms()` has no wasm branch and falls to
   the `HOSTTYPE` fallback. A real `wasm32-unknown-emscripten` platform is cleaner and upstream-correct.
4. **Native benchmark.** The README's "CPU — native (Spike B oracle)" numbers (~619 / ~2,629
   M kernel-iters/s) are actually produced by a **Node.js** script (`wasm/spikes/spikeB-webgpu/oracle.js`),
   not compiled native code. No committed native benchmark exists. Add one so the numbers are genuinely
   native and reviewer-reproducible.

Decisions (confirmed): platform name **`wasm32-unknown-emscripten`**; **automate** the server build
with a script; **full end-to-end** verification.

---

## Item 1 — reproducible from-source server (automated)
**New `wasm/server/build_base_images.sh`** — encapsulates the from-source base-image build proven this
session:
- Locate the sibling `boinc-server-docker` repo (`$HOME/boinc-server-docker`, else clone
  `https://github.com/marius311/boinc-server-docker`).
- Populate its `images/makeproject/boinc` from **this** repo (rsync, exclude `3rdParty/wasm/emsdk`,
  `.git`, `*.o/*.lo/*.la/*.a`, `.libs`, `.deps`, `*.wasm`, `config.h`) so the compiled scheduler
  includes the fix.
- Build + tag the exact images `wasm/server` consumes, using boinc-server-docker's `.env`
  (`VERSION=latest`, `BOINC_USER=boincadm`, `PROJECT_ROOT=/home/boincadm/project`):
  - `docker compose build mysql makeproject` with `DEFAULTARGS=-defaultargs`
    → `boinc/server_{mysql,makeproject}:latest-defaultargs`
  - `docker build --target apache -t boinc/server_apache:latest images/apache` (ONBUILD-extensible
    base the `wasm/server` Dockerfile `FROM`s; needs `DEFAULTARGS` empty).

**Update `wasm/server/README.md`** — add a "Build with the fix (from source)" section: explain the
prebuilt images are v7.15 without the fix, then `./build_base_images.sh && docker compose up --build -d`.

Files: `wasm/server/build_base_images.sh` (new), `wasm/server/README.md`.

## Item 3 — `wasm32-unknown-emscripten` platform (all touch-points together)
- **Client** `client/cs_platforms.cpp` `detect_platforms()`: add a branch guarded by `#ifdef WASM`
  (or `defined(__EMSCRIPTEN__)`) that `add_platform("wasm32-unknown-emscripten")` as the primary,
  instead of the `HOSTTYPE` fallback (`i686-pc-linux-gnu`). Self-contained; no `--host`/m4 change
  (keeps the emconfigure build untouched — the native `$target` can't key a wasm case anyway).
- **Server platform registry** `tools/project.xml`: add
  `<platform><name>wasm32-unknown-emscripten</name><user_friendly_name>WebAssembly</user_friendly_name></platform>`
  so `bin/xadd` inserts the DB row. No code change to `xadd`/`update_versions`/`db/schema.sql`.
- **Registration** `wasm/server/register_wasm_app.sh`: `PLATFORM=wasm32-unknown-emscripten`; app-version
  dirs become `apps/sample/1.0/wasm32-unknown-emscripten[ __webgpu]`.
- Rebuild the client (`wasm/ci_configure_client.sh && wasm/ci_make.sh`) so the new platform is reported;
  the from-source server rebuild (Item 1) re-COPYs the new client + picks up the project.xml platform.

Files: `client/cs_platforms.cpp`, `tools/project.xml`, `wasm/server/register_wasm_app.sh` (+ client rebuild).
Risk: the client-reported string, the `project.xml`/DB platform row, and the app-version dir names must
stay consistent or the scheduler finds no app version and sends no work — all changed together here.

## Item 4 — committed native benchmark (real "native" numbers)
- **New `wasm/spikes/spikeB-webgpu/native_bench.c`** — standalone C, no BOINC deps. The exact xorshift32
  kernel from `wasm/gpu_app/gpu_app.cpp:20-28` (input `x = i*2654435761 + 1`; `K=256` iters of
  `x^=x<<13; x^=x>>17; x^=x<<5`; XOR-fold over `N=1<<20`). Asserts checksum `== 0x27a723a9`; prints
  M kernel-iters/s for 1 thread and for N threads (pthreads split the i-loop + XOR-fold partials,
  mirroring `oracle.js`/`cpu-worker.js`).
- **New `wasm/spikes/spikeB-webgpu/build_native_bench.sh`** — `cc -O2 -pthread native_bench.c -o
  native_bench` (model: `wasm/benchmark/build_benchmark.sh`).
- **Update `wasm/README.md` §4i** — correct the "(Spike B oracle)" rows (they were Node.js, not native);
  cite `native_bench.c` and the re-measured numbers; keep the bit-exact checksum as the correctness anchor.

Files: `wasm/spikes/spikeB-webgpu/native_bench.c` (new), `build_native_bench.sh` (new), `wasm/README.md`.

---

## Verification (full end-to-end)
1. **#4 (fast, standalone):** `bash wasm/spikes/spikeB-webgpu/build_native_bench.sh && ./native_bench`
   → checksum `0x27a723a9` + 1-thread and N-thread rates; write the real numbers into README §4i.
2. **#3 client:** rebuild the wasm client; confirm it reports `wasm32-unknown-emscripten`
   (grep the client log / a scheduler request).
3. **#1 + #3 server:** `wasm/server/build_base_images.sh` (from-source images incl. the fix) →
   `docker compose up --build -d`; confirm the `wasm32-unknown-emscripten` platform row exists in the DB
   and both app versions are registered under it.
4. **Live browser demo:** open `http://127.0.0.1/wasm/` in Chrome (via the existing port-forward);
   confirm the client reports `wasm32-unknown-emscripten` + the `webgpu` coproc, the scheduler dispatches
   `plan_class=webgpu` under the new platform, tasks report SUCCESS (bit-exact `0x27a723a9`), and no
   scheduler warnings appear.
5. Present commit message(s) — the user commits (per their workflow).

## Notes
- Order: #4 → #3 client → #1+#3 server → browser demo (each verifiable before the next).
- The from-source server build is ~15–20 min; the browser step needs you to open Chrome.
- All git commits are done by the user.
