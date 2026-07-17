# Phase 0 — de-risk spikes

Two self-contained spikes that validate the two riskiest unknowns of the browser-BOINC plan
*before* touching the BOINC tree. See `../README.md` for the full plan.

| Spike | Risk it de-risks | Runs headless here? |
| --- | --- | --- |
| **A — IPC** | Can a SharedArrayBuffer replace BOINC's `fork()`+SysV-shmem `APP_CLIENT_SHM` process model? | **Yes** (Node) — plus a browser page |
| **B — WebGPU** | Can we detect the GPU and run a compute kernel that matches the CPU bit-for-bit, and is it faster? | Kernel/CPU: **yes** (Node). GPU dispatch: **browser only** |

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
