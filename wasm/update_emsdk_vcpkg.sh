#!/bin/sh
set -e

if [ ! -d "wasm" ]; then
    echo "start this script in the source root directory"
    exit 1
fi

. "$PWD/3rdParty/vcpkg_ports/vcpkg_link.sh"
BUILD_DIR="$PWD/3rdParty/wasm"
VCPKG_PORTS="$PWD/3rdParty/vcpkg_ports"
VCPKG_ROOT="$BUILD_DIR/vcpkg"

if [ ! -d "$VCPKG_ROOT" ]; then
    mkdir -p "$BUILD_DIR"
    git -C "$BUILD_DIR" clone --depth 1 "$VCPKG_LINK"
fi

"$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics
"$VCPKG_ROOT/vcpkg" install \
    --x-manifest-root="$VCPKG_PORTS/configs/client/wasm" \
    --x-install-root="$VCPKG_ROOT/installed" \
    --overlay-ports="$VCPKG_PORTS/ports" \
    --overlay-triplets="$VCPKG_PORTS/triplets/ci" \
    --triplet=wasm32-emscripten --clean-after-build
