#!/bin/sh
set -e

#
# See: http://boinc.berkeley.edu/trac/wiki/AndroidBuildClient#
#

# Script to compile IXWEBSOCKET for Android

STDOUT_TARGET="${STDOUT_TARGET:-/dev/stdout}"
CONFIGURE="yes"
MAKECLEAN="yes"
VERBOSE="${VERBOSE:-no}"
NPROC_USER="${NPROC_USER:-1}"

IXWEBSOCKET="${IXWEBSOCKET_SRC:-$HOME/src/IXWEBSOCKET-11.4.3}" #IXWEBSOCKET sources, required by BOINC

export NDK_ROOT=${NDK_ROOT:-$HOME/Android/Ndk}
export ANDROID_TC="${ANDROID_TC:-$HOME/android-tc}"
export ANDROIDTC="${ANDROID_TC_ARM64:-$ANDROID_TC/arm64}"
export TOOLCHAINROOT="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64"
export TCBINARIES="$TOOLCHAINROOT/bin"
export TCINCLUDES="$ANDROIDTC/aarch64-linux-android"
export TCSYSROOT="$TOOLCHAINROOT/sysroot"

export PATH="$TCBINARIES:$TCINCLUDES/bin:$PATH"
export CC=aarch64-linux-android21-clang
export CXX=aarch64-linux-android21-clang++
export LD=aarch64-linux-android-ld
export CFLAGS="--sysroot=$TCSYSROOT -DANDROID -Wall -I$TCINCLUDES/include -O3 -fomit-frame-pointer -fPIE -D__ANDROID_API__=21 -Dchar16_t=uint16_t -Dchar32_t=uint32_t"
export CXXFLAGS="--sysroot=$TCSYSROOT -DANDROID -Wall -I$TCINCLUDES/include -funroll-loops -fexceptions -O3 -fomit-frame-pointer -fPIE -D__ANDROID_API__=21 -Dchar16_t=uint16_t -Dchar32_t=uint32_t"
export LDFLAGS="-L$TCSYSROOT/usr/lib -L$TCINCLUDES/lib -llog -fPIE -pie -latomic -static-libstdc++"
export GDB_CFLAGS="--sysroot=$TCSYSROOT -Wall -g -I$TCINCLUDES/include"

MAKE_FLAGS=""

if [ $VERBOSE = "no" ]; then
    MAKE_FLAGS="$MAKE_FLAGS --silent"
else
    MAKE_FLAGS="$MAKE_FLAGS SHELL=\"/bin/bash -x\""
fi

if [ $CI = "yes" ]; then
    MAKE_FLAGS1="$MAKE_FLAGS -j $(nproc --all)"
else
    MAKE_FLAGS1="$MAKE_FLAGS -j $NPROC_USER"
fi

if [ ! -e "${IXWEBSOCKET_FLAGFILE}" -a  $BUILD_WITH_VCPKG = "no" ]; then
    mkdir -p "$IXWEBSOCKET/build-arm64"
    cd "$IXWEBSOCKET/build-arm64"
    echo "===== building IXWEBSOCKET for arm64 from $PWD ====="
    if [ -n "$MAKECLEAN" -a -e "${IXWEBSOCKET}/Makefile" ]; then
        if [ "$VERBOSE" = "no" ]; then
            make clean 1>$STDOUT_TARGET 2>&1
        else
            make clean SHELL="/bin/bash -x"
        fi
    fi
    if [ -n "$CONFIGURE" ]; then
        cmake .. \
            -DCMAKE_INSTALL_PREFIX="$TCINCLUDES" \
            -DOPENSSL_CRYPTO_LIBRARY="$TCINCLUDES\lib" \
            -DOPENSSL_SSL_LIBRARY="$TCINCLUDES\lib" \
            -DOPENSSL_INCLUDE_DIR="$TCINCLUDES\include" \
            -DCMAKE_CXX_STANDARD=11 \
            -DANDROID_NDK="$NDK_ROOT" \
            -DCMAKE_TOOLCHAIN_FILE=$NDK_ROOT/build/cmake/android.toolchain.cmake \
            -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
            -DANDROID_ABI=arm64-v8a \
            -DANDROID_PLATFORM=android-21 \
            -DCMAKE_ANDROID_ARCH_ABI=arm64-v8a \
            -DCMAKE_SYSTEM_NAME=Android \
            -DCMAKE_SYSTEM_VERSION=21 \
            -DANDROID_STL=c++_static \
            -DUSE_TLS=ON \
            1>$STDOUT_TARGET
    fi
    if [ $VERBOSE = "no" ]; then
        echo MAKE_FLAGS=$MAKE_FLAGS "1>$STDOUT_TARGET"
        make $MAKE_FLAGS 1>$STDOUT_TARGET
        make install $MAKE_FLAGS 1>$STDOUT_TARGET
    else
        echo MAKE_FLAGS=$MAKE_FLAGS
        make $MAKE_FLAGS
        make install $MAKE_FLAGS
    fi
    
    touch "${IXWEBSOCKET_FLAGFILE}"
    echo "\e[1;32m===== IXWEBSOCKET for arm64 build done =====\e[0m"
fi
