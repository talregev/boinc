#!/bin/sh
set -e

if [ ! -d "wasm" ]; then
    echo "start this script in the source root directory"
    exit 1
fi

CACHE_DIR="$PWD/3rdParty/buildCache/wasm"
BUILD_DIR="$PWD/3rdParty/wasm"
VCPKG_ROOT="$BUILD_DIR/vcpkg"

export XDG_CACHE_HOME=$CACHE_DIR/vcpkgcache

if [ ! -d $VCPKG_ROOT ]; then
    mkdir -p $BUILD_DIR
    git -C $BUILD_DIR clone https://github.com/microsoft/vcpkg
fi

git -C $VCPKG_ROOT pull
$VCPKG_ROOT/bootstrap-vcpkg.sh
$VCPKG_ROOT/vcpkg install rappture curl[core,openssl] --triplet=wasm32-emscripten --clean-after-build
$VCPKG_ROOT/vcpkg upgrade --no-dry-run
