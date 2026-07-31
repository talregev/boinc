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
# -pthread: WasmFS's OPFS backend runs on a dedicated thread, so the whole client must be built
# shared-memory-aware (compile + link). The client itself stays single-threaded; only OPFS uses a thread.
export CPPFLAGS="-msimd128 -pthread"
# Link flags:
# - grow memory on demand + a real stack (the 64 KB default overflows on real work);
# - export ccall/UTF8ToString + malloc/free so the web UI can call the GUI RPC bridge
#   (boinc_handle_gui_rpc, kept via EMSCRIPTEN_KEEPALIVE) and free its malloc'd reply.
# - WasmFS + OPFS: back the data dir with the Origin Private File System (real disk-backed,
#   random-access, durable storage) so client_state.xml, projects and tasks survive page reloads.
#   The client runs in a Web Worker (see wasm/browser/client_worker.js), so OPFS sync access
#   handles are usable; the OPFS backend is mounted at /boinc_data in C at main() start
#   (client/main.cpp). Needs -pthread (the OPFS backend runs on a dedicated thread) + a small
#   pthread pool so the backend thread is ready without a spawn round-trip.
# - FETCH: HTTP transport for HTTP_OP via emscripten_fetch (libcurl sockets can't reach
#   servers from a browser); see client/http_curl.cpp wasm_fetch_exec.
# NB: --embed-file (the CPU benchmark module) is NOT here — it's scoped to the client link in
# client/Makefile.am (BUILD_WITH_WASM), because --embed-file + -sWASMFS breaks autoconf's compiler
# check (its no-output conftest auto-enables NODERAWFS, which forbids --embed-file).
export LDFLAGS="-sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=5MB -sINITIAL_MEMORY=64MB -sFETCH \
-sWASMFS -pthread -sPTHREAD_POOL_SIZE=4 \
-sEXPORTED_RUNTIME_METHODS=ccall,cwrap,UTF8ToString -sEXPORTED_FUNCTIONS=_main,_malloc,_free \
--pre-js $PWD/wasm/browser/webgpu_pre.js"
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
