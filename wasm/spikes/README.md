# De-risk spikes

Self-contained spikes that validate the riskiest unknowns of the browser-BOINC plan *before* touching
the BOINC tree. A and B are the Phase-0 spikes; C is the Phase-2 (OPFS) de-risk. See `../README.md`
for the full plan.

| Spike | Risk it de-risks | Runs headless here? |
| --- | --- | --- |
| **A — IPC** | Can a SharedArrayBuffer replace BOINC's `fork()`+SysV-shmem `APP_CLIENT_SHM` process model? | **Yes** (Node) — plus a browser page |
| **B — WebGPU** | Can we detect the GPU and run a compute kernel that matches the CPU bit-for-bit, and is it faster? | Kernel/CPU: **yes** (Node). GPU dispatch: **browser only** |
| **C — WasmFS/OPFS** | Can the client run in a Worker with an OPFS-backed persistent data dir, plus `-pthread`, nested Workers, `emscripten_fetch`, and WebGPU — all off the main thread? | **Browser only** (OPFS) |

## Spike A — client ⇄ app IPC (`spikeA-ipc/`)
- `shm.js` — UMD emulation of `APP_CLIENT_SHM`'s `MSG_CHANNEL`s over a SharedArrayBuffer (Atomics).
- `app-worker.js` / `client.js` — Node harness (science app in a worker_thread, client + assertions).
- `index.html` / `app-worker-browser.js` — the same protocol in a real browser (page=client, Worker=app).

Run headless:
```
node spikeA-ipc/client.js        # exits 0 on PASS
```
Run in a browser (needs cross-origin isolation for SharedArrayBuffer):
```
python3 serve.py                 # then open http://localhost:8000/spikeA-ipc/
```

## Spike B — WebGPU detect + compute (`spikeB-webgpu/`)
- `kernel.js` — reference xorshift32 kernel (shared by Node and browser).
- `compute.wgsl` — the WebGPU compute shader, kept bit-for-bit identical to `kernel.js`.
- `oracle.js` — headless: cross-checks the kernel against an independent BigInt impl, benchmarks the
  single-thread **and all-cores** (`cpu-worker.js`) CPU baselines, and prints the target checksum.
- `cpu-worker.js` / `cpu-worker-browser.js` — one CPU worker (Node / browser) computing a slice for
  the all-cores baseline.
- `index.html` — detects the GPU adapter (name/limits) and runs the shader, comparing its checksum
  and timing to the single-thread and all-cores CPU baselines.

Both pages POST their result JSON to the server's `/report` endpoint (`serve.py` appends to
`runs.jsonl`), so a run's numbers can be read back without copy-paste.

Run headless (verifies the kernel + prints the target checksum):
```
node spikeB-webgpu/oracle.js     # exits 0 on PASS
```
Run the GPU on a WebGPU browser (Chrome/Edge; Firefox needs dom.webgpu.enabled):
```
python3 serve.py                 # then open http://localhost:8000/spikeB-webgpu/
# PASS = "GPU checksum == CPU checksum" and a speedup number
```

## Spike C — WasmFS + OPFS in a Worker (`spikeC-worker-opfs/`)
The Phase-2 de-risk: run a wasm module off the browser main thread (in a Worker) using WasmFS's OPFS
backend for a real, disk-backed, persistent data dir — alongside everything the client needs.
- `spike.c` — mounts OPFS at `/data`; increments a counter file (proves persistence across reloads);
  reads an `--embed-file`; spawns a nested Worker; checks `navigator.gpu`; POSTs the result JSON.
- `index.html` / `serve.py` — host it (COOP/COEP; `serve.py` logs the POSTed result to `runs.jsonl`).

**Key finding:** OPFS **requires `-pthread`** — its backend runs on a dedicated thread; a no-pthread
build crashes in `opfs_backend.cpp`, and emscripten lists an async/no-thread OPFS variant as a TODO.
So the client, and every library it links (curl/openssl/zlib), must be built shared-memory-aware
(see `../ci_configure_client.sh` and the vcpkg `-pthread` triplet).

Build + run in a WebGPU, cross-origin-isolated browser:
```
emcc spike.c -sWASMFS -pthread -sPROXY_TO_PTHREAD -sFETCH -sALLOW_MEMORY_GROWTH \
  --embed-file embed.txt@/embed.txt -o spike.js
python3 serve.py 8099             # then open http://localhost:8099/
# PASS = the counter increments across reloads (OPFS persisted) + opfs_mount_rc=0
```
