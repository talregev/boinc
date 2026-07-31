#!/bin/bash
# Build the standalone CPU benchmark (Whetstone + Dhrystone) to wasm, run by the client in a Web
# Worker (client/cs_benchmark.cpp). Produces benchmark.js + benchmark.wasm here, which are embedded
# into the client at link time (wasm/ci_configure_client.sh). Run from the source root or this dir.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EMSDK_ROOT="$ROOT/3rdParty/wasm/emsdk"
source "$EMSDK_ROOT/emsdk_env.sh"

cd "$ROOT"
em++ wasm/benchmark/benchmark.cpp \
    client/whetstone.cpp client/dhrystone.cpp client/dhrystone2.cpp \
    -DWASM -D_GNU_SOURCE -I. -Ilib -Iclient \
    -O2 -sEXIT_RUNTIME=1 \
    lib/.libs/libboinc.a \
    -o wasm/benchmark/benchmark.js

echo "built wasm/benchmark/benchmark.js + benchmark.wasm"
