#!/bin/bash
set -e

if [ ! -d "wasm" ]; then
    echo "start this script in the source root directory"
    exit 1
fi

BUILD_DIR="$PWD/3rdParty/wasm"
EMSDK_ROOT="$BUILD_DIR/emsdk"

source "$EMSDK_ROOT/emsdk_env.sh"
# Build libboinc first, then the CPU benchmark module (it links libboinc and is --embed-file'd into
# the client, so it must exist before the client links), then the rest.
emmake make -C lib -j$(nproc)
bash wasm/benchmark/build_benchmark.sh
emmake make -j$(nproc)
