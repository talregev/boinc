# WASM BOINC demo server (Phase 7)

A reproducible, real BOINC project server (MySQL + Apache + BOINC daemons) that serves the WebAssembly
BOINC client and a real wasm science app — so a browser can run genuine BOINC work end-to-end against
a real scheduler, validator, and DB (not the Python mock in `wasm/sample_app/`).

It extends the official [`boinc-server-docker`](https://github.com/BOINC/boinc-server-docker) images
with three things: the wasm client page (served same-origin with COOP/COEP), the wasm app registered
as an app version, and a demo account — all wired up automatically at `docker compose up`.

## Prerequisites
- Docker + `docker compose`.
- The wasm client and apps built (git-ignored artifacts the image `COPY`s in):
  ```
  wasm/ci_configure_client.sh && wasm/ci_make.sh   # -> client/boinc_client.{js,wasm}
  wasm/sample_app/build_app.sh                       # -> wasm/sample_app/app.{js,wasm}
  wasm/gpu_app/build_app.sh                          # -> wasm/gpu_app/app_gpu.{js,wasm}
  ```
- **For GPU-typed scheduling** (a host reporting the `webgpu` coproc receiving the
  `plan_class=webgpu` app version), the server needs the generic-coproc scheduler fix
  (`sched/plan_class_spec.cpp`) — which the **prebuilt Docker Hub images predate**. Build the base
  images from THIS source once:
  ```
  wasm/server/build_base_images.sh   # boinc/server_{mysql,makeproject,apache} built from this tree
  ```
  Without it the demo still runs the CPU path, but the scheduler won't emit the `<coproc>webgpu`
  requirement.

## Run
```
cd wasm/server
docker compose up --build -d
```
The first run pulls the base images and creates the project (a minute or two). Then open
**http://127.0.0.1/wasm/** in a cross-origin-isolated, WebGPU-capable browser. The page loads the
wasm client, creates a demo account, attaches to this server, downloads the app, runs it in a Web
Worker, and reports the result — visible in the two log panels.

Verify from the shell:
```
curl http://127.0.0.1/boincserver/                     # master file (200)
curl http://127.0.0.1/wasm/                            # client page (200, COOP/COEP headers)
docker compose exec apache mysql -h mysql -uroot -ppassword boincserver -N \
  -e 'select name,plan_class from app_version; select count(*) from result;'
```

## Teardown
```
docker compose down -v      # -v also wipes the project DB + volumes
```

## How it works
- `docker-compose.yml` — `mysql`, a one-shot `makeproject` (creates the project), and our `apache`
  (built from `Dockerfile`). `apache` waits for `makeproject` to finish (`service_completed_successfully`).
- `Dockerfile` — extends `boinc/server_apache`, enables `mod_headers`, adds `apache-wasm.conf`
  (serves `/wasm` with COOP/COEP), copies the client + app files, and installs the registration hook.
- `register_wasm_app.sh` — runs once at startup (supervisord): generates a code-signing key, adds the
  `sample` app, stages the app version (`app.js` main + `app.wasm`), `update_versions`, `create_work`,
  and pre-creates the demo account (`/wasm/account.txt`). Idempotent.

## Notes / limitations
- **GPU app:** to demo the WebGPU app instead, build `wasm/gpu_app/build_app.sh` and point the
  `Dockerfile`'s app `COPY` at `wasm/gpu_app/app.{js,wasm}`. It runs on the GPU internally.
- **GPU-*typed* scheduling** (a `webgpu` plan class the scheduler targets) needs a generic coproc
  branch in `sched/plan_class_spec.cpp` — deliberately not added here (see `wasm/phase7-plan.md`), so
  the app is registered as a normal (CPU-scheduled) version. GPU-typed matching is demonstrated with
  the mock (`wasm/sample_app/mock_project.py`, Phase 7 Stage 7.1).
- The wasm client reports platform `i686-pc-linux-gnu` (the build's `HOSTTYPE`); the app version is
  registered under that platform. A dedicated `wasm` platform is a later improvement.
- Same-origin hosting (client page + scheduler + downloads all on `127.0.0.1:80`) avoids CORS; only
  COOP/COEP are needed, for SharedArrayBuffer.
