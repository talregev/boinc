#!/bin/sh

#!/bin/sh
set -e

if [ ! -d "linux" ]; then
    echo "start this script in the source root directory"
    exit 1
fi

CMAKE_VERSION="3.28.2"
IXWEBSOCKET_VERSION="11.4.3"
WGET_VERSION="1.21.2"
BUILD_DIR="$PWD/3rdParty/linux"
IXWEBSOCKET_ROOT="$BUILD_DIR/IXWebSocket"
LINK="https://github.com/machinezone/IXWebSocket -b v$IXWEBSOCKET_VERSION"

if [ ! -d $IXWEBSOCKET_ROOT ]; then
    mkdir -p $BUILD_DIR
    export GIT_SSL_NO_VERIFY=1
    git clone $LINK $IXWEBSOCKET_ROOT
fi

mkdir $IXWEBSOCKET_ROOT/build
cd $IXWEBSOCKET_ROOT/build

wget --no-check-certificate http://www.openssl.org/source/openssl-3.2.0.tar.gz
tar -xvzf openssl-3.2.0.tar.gz
cd openssl-3.2.0/
./Configure --openssldir=/usr --prefix=/usr
make install
cd ..

wget --version
wget http://ftp.gnu.org/gnu/wget/wget2-2.1.0.tar.gz
tar -xvzf wget2-2.1.0.tar.gz
cd wget2-2.1.0
./configure --prefix=/usr --with-ssl
make install
cd ..
wget2 --version

wget2 --no-check-certificate https://github.com/Kitware/CMake/releases/download/v3.28.2/cmake-3.28.2-linux-x86_64.tar.gz
tar -xvzf cmake-3.28.2-linux-x86_64.tar.gz
cmake-3.28.2-linux-x86_64/bin/cmake .. -DUSE_TLS=ON
make
make install
