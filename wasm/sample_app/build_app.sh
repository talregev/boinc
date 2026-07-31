#!/bin/bash
# Build the CPU sample science app (sample_app.cpp) to wasm, against the real libboinc_api
# (api/boinc_api.cpp compiled with -DWASM) + libboinc.a. Produces app.js + app.wasm here.
# Run this from the source root or this dir.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EMSDK_ROOT="$ROOT/3rdParty/wasm/emsdk"
source "$EMSDK_ROOT/emsdk_env.sh"

cd "$ROOT"
em++ wasm/sample_app/sample_app.cpp api/boinc_api.cpp \
    -DWASM -D_GNU_SOURCE -I. -Ilib -Iapi \
    -O2 -sEXIT_RUNTIME=1 \
    lib/.libs/libboinc.a \
    -o wasm/sample_app/app.js

echo "built wasm/sample_app/app.js + app.wasm"
