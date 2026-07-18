# Phase 7 — Demo project server + hosting (staged plan)

Phase 7 replaces the Python mock (`wasm/sample_app/mock_project.py`) with a **real BOINC project
server**, and makes the scheduler *target the GPU*: it should choose the WebGPU app version for hosts
that report the `webgpu` coproc, and the plain CPU version otherwise. It also covers hosting — serving
the wasm client cross-origin-isolated (COOP/COEP) with CORS so it can attach to the project.

Status of the prerequisites (done in Phases 0–6, on `master`):
- Client detects the WebGPU adapter and registers it as a schedulable `webgpu` coproc, and **sends it
  in the scheduler request** (`Requesting new tasks for CPU and webgpu`).
- A GPU-typed app version (`plan_class=webgpu` + a `<coproc>` requirement) is accepted and scheduled
  on that coproc — proven with the mock (`plan_class="webgpu"`).
- CPU and WebGPU sample apps exist (`wasm/sample_app/`, `wasm/gpu_app/`) and run the full cycle.

The one thing the mock can't do: **decide** which app version to send based on the host's coprocs.
That's a real *server* responsibility and is the heart of Phase 7.

Grounding facts (verified in the source):
- The scheduler already parses the generic `<coproc>` from the request (`lib/coproc.cpp` `COPROCS::parse`),
  and the client already writes the `webgpu` coproc generically — so the data reaches the server.
- But `sched/plan_class_spec.cpp` matching is **hardwired to the big-4 GPU types**
  (`sreq.coprocs.ati/.nvidia/.intel_gpu`, ~line 679). A `webgpu` plan class needs a new branch that
  looks up the generic coproc (`sreq.coprocs.lookup_type("webgpu")`, `count>0`).
- Docker is available in this environment; the repo has the server (`sched/`) and `tools/make_project`.

Working method: each stage is a checkpoint — verify before moving on; flag early if the Docker
bring-up (7.2) starts rabbit-holing rather than burning hours silently.

---

## Stage 7.1 — Server-side plan-class matching  *(verifiable now, light)*
Make the scheduler choose the WebGPU vs CPU app version from the host's reported coprocs.

- **Real server code** — `sched/plan_class_spec.cpp`: add a `webgpu` `gpu_type` branch that looks up
  the generic `webgpu` coproc in `sreq.coprocs` (`lookup_type("webgpu")`, require `count>0`). Add a
  `webgpu` plan class to `sched/plan_class_spec.xml.sample`.
- **Mock** — `wasm/sample_app/mock_project.py`: parse the request's `<coproc><type>webgpu</type>`;
  send the WebGPU app version only if present, else the CPU version. Log the decision.
- **Verify:** Chrome (GPU host → `plan_class="webgpu"`) + a `curl` request without the coproc → CPU
  version.
- **Deliverable:** matching logic proven end-to-end; the upstream `sched/` change written.

## Stage 7.2 — Real BOINC server bring-up (Docker)  *(heavy infra)*
- Stand up MySQL + Apache + BOINC daemons in Docker; create a project with `tools/make_project`.
- **Verify:** scheduler responds, project web pages serve, DB initialized (checkpoint with `curl`
  before proceeding — this is the infra-risk stage).

## Stage 7.3 — Register the wasm + WebGPU app versions
- Add the `sample` app; register the **CPU** app version (empty plan_class) and the **WebGPU** version
  (`plan_class=webgpu`) with `app.js`/`app.wasm`. Anonymous-platform / `unsigned_apps_ok` (already set
  by the client). Create workunits (`create_work`).
- **Verify:** the real scheduler offers a task.

## Stage 7.4 — Hosting: COOP/COEP + CORS + client page
- Configure Apache: CORS (so the client's `emscripten_fetch` reaches the scheduler/downloads
  cross-origin) + COOP/COEP for the client page; serve a static page that loads `boinc_client.js`.
- **Verify:** the client page loads cross-origin-isolated and reaches the real scheduler.

## Stage 7.5 — End-to-end against the real server
- Attach the browser client to the real project.
- **Verify:** real scheduler → **plan-class matching sends the WebGPU version** (host reports the
  `webgpu` coproc) → download → GPU crunch → upload → real validator/assimilator → task reported.
- **Deliverable:** a real, hostable BOINC project running wasm + WebGPU apps in the browser, with the
  scheduler targeting the GPU.

---

### Open questions / risks
- **Server build**: building `sched/` needs the server toolchain (`configure --enable-server`, MySQL
  dev libs) — done inside the Docker image in 7.2, which also compile-checks the 7.1 code change.
- **Cross-origin isolation**: the client page needs COOP/COEP (for `SharedArrayBuffer`); the project
  is a different origin, so downloads/scheduler need CORS. Both are configured in 7.4.
- **App-version signing**: browsers have no code-signing; rely on `unsigned_apps_ok` (client already
  sets it) + anonymous platform.
- **`plan_class_spec.cpp` generality**: prefer a minimal generic-coproc branch over a big-4-style
  special case, mirroring how the *client* stayed generic (no new `PROC_TYPE`).
