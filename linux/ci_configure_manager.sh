#!/bin/sh
set -e

if [ ! -d "linux" ]; then
    echo "start this script in the source root directory"
    exit 1
fi

CACHE_DIR="$PWD/3rdParty/buildCache/linux"
BUILD_DIR="$PWD/3rdParty/linux"
VCPKG_ROOT="$BUILD_DIR/vcpkg"
export VCPKG_DIR="$VCPKG_ROOT/installed/x64-linux"

linux/update_vcpkg_manager.sh

export _libcurl_pc="$VCPKG_DIR/lib/pkgconfig/libcurl.pc"
export PKG_CONFIG_PATH=$VCPKG_DIR/lib/pkgconfig/
export CPPFLAGS="-DwxDEBUG_LEVEL=0 -I$VCPKG_DIR/include" 
export LDFLAGS="-L$VCPKG_DIR/lib"
export GTK_LIBS="$(pkg-config --libs gtk+-3.0)"
./configure --enable-vcpkg --disable-server --disable-client --with-wx-config=$VCPKG_DIR/tools/wxwidgets/wx-config
