#!/bin/bash
set -e

if [ ! -d "wasm" ]; then
    echo "start this script in the source root directory"
    exit 1
fi

BUILD_DIR="$PWD/3rdParty/wasm"
EMSDK_ROOT="$BUILD_DIR/emsdk"
VCPKG_ROOT="$BUILD_DIR/vcpkg"
export VCPKG_DIR="$VCPKG_ROOT/installed/wasm32-emscripten"

wasm/update_emsdk.sh
source "$EMSDK_ROOT/emsdk_env.sh"
wasm/update_emsdk_vcpkg.sh

# Enable WASM SIMD (WebAssembly 3.0) for the numeric paths.
export CPPFLAGS="-msimd128"
# Link flags: grow memory on demand and give a real stack (the 64 KB default overflows
# as soon as the client does non-trivial work). Applied at configure time.
export LDFLAGS="-sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=5MB -sINITIAL_MEMORY=64MB"
debug_flags=""

if [ "debug" == "$1" ]; then
    export CPPFLAGS="$CPPFLAGS -g3 -fdebug-prefix-map=$PWD=.."
    debug_flags="--enable-debug"
    echo -e "\e[33mDebug flags: ./configure $debug_flags, CPPFLAGS=$CPPFLAGS\e[0m"
fi

export _libcurl_pc="$VCPKG_DIR/lib/pkgconfig/libcurl.pc"
export PKG_CONFIG_PATH="$VCPKG_DIR/lib/pkgconfig/"
# emconfigure wipes PKG_CONFIG_PATH and pins PKG_CONFIG_LIBDIR to the emscripten sysroot;
# EM_PKG_CONFIG_PATH is Emscripten's escape hatch to add our vcpkg .pc files (curl needs openssl.pc).
export EM_PKG_CONFIG_PATH="$VCPKG_DIR/lib/pkgconfig"
emconfigure ./configure $debug_flags --enable-wasm --with-libcurl="$VCPKG_DIR" --with-ssl="$VCPKG_DIR" --disable-server --enable-client --disable-manager
