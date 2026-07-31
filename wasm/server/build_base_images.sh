#!/bin/bash
# Build the boinc-server-docker base images FROM THIS BOINC source, so the wasm demo server includes
# the generic-coproc scheduler fix (sched/plan_class_spec.cpp). The prebuilt boinc/server_* images on
# Docker Hub are an older BOINC and lack it, so a clean-clone `docker compose up` would send the
# webgpu app version WITHOUT the <coproc> requirement. Run this once before bringing up wasm/server:
#
#     wasm/ci_configure_client.sh && wasm/ci_make.sh     # build the client first (Dockerfile COPYs it)
#     wasm/sample_app/build_app.sh && wasm/gpu_app/build_app.sh
#     wasm/server/build_base_images.sh                   # <-- this: base images from THIS source
#     cd wasm/server && docker compose up --build -d
set -e

BOINC_SRC="$(cd "$(dirname "$0")/../.." && pwd)"          # repo root
BSD="${BOINC_SERVER_DOCKER:-$HOME/boinc-server-docker}"   # sibling boinc-server-docker checkout

if [ ! -d "$BSD" ]; then
    echo "[base-images] cloning boinc-server-docker into $BSD"
    git clone https://github.com/BOINC/boinc-server-docker.git "$BSD"
fi

echo "[base-images] populating $BSD/images/makeproject/boinc from $BOINC_SRC (this source)"
rsync -a --delete \
    --exclude '3rdParty/wasm/emsdk' --exclude '.git' --exclude '.libs' --exclude '.deps' \
    --exclude '*.o' --exclude '*.lo' --exclude '*.la' --exclude '*.a' \
    --exclude '*.wasm' --exclude '*.bc' --exclude 'config.h' --exclude 'Makefile' \
    "$BOINC_SRC/" "$BSD/images/makeproject/boinc/"

cd "$BSD"
export VERSION=latest TAG= DEFAULTARGS=-defaultargs
export BOINC_USER=boincadm PROJECT_ROOT=/home/boincadm/project
export URL_BASE=http://127.0.0.1 PROJECT=boincserver

echo "[base-images] building boinc/server_{mysql,makeproject}:latest-defaultargs (compiles BOINC)…"
docker compose build mysql makeproject

# wasm/server/Dockerfile does `FROM boinc/server_apache:latest` (the ONBUILD-extensible, non-defaultargs
# variant), so build that tag too.
echo "[base-images] building boinc/server_apache:latest (ONBUILD base for wasm/server/Dockerfile)…"
docker build --target apache -t boinc/server_apache:latest --build-arg TAG= images/apache

echo "[base-images] done. Next: cd $BOINC_SRC/wasm/server && docker compose up --build -d"
