#!/bin/sh

# This file is part of BOINC.
# http://boinc.berkeley.edu
# Copyright (C) 2008 University of California
#
# BOINC is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# BOINC is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with BOINC.  If not, see <http://www.gnu.org/licenses/>.
#
#
# Script to build Macintosh wrapper using Makefile
#
# by Charlie Fenton 2/15/10
# Updated 11/16/11 for XCode 4.1 and OS 10.7 
# Updated 7/12/12 for Xcode 4.3 and later which are not at a fixed address
# Updated 8/28/20 for compatibility with Xcode 10
# Updated 8/19/22 to build Universal M1 / x86_64 binary
#
## This script requires OS 10.6 or later
#
## If you drag-install Xcode 4.3 or later, you must have opened Xcode 
## and clicked the Install button on the dialog which appears to 
## complete the Xcode installation before running this script.
#
## First, build the BOINC libraries using boinc/mac_build/BuildMacBOINC.sh
##
## In Terminal, CD to the wrqpper directory.
##     cd [path]/wrapper/
## then run this script:
##     sh [path]/BuildMacWrapper.sh
##

GCCPATH=`xcrun -find gcc`
if [  $? -ne 0 ]; then
    echo "ERROR: can't find gcc compiler"
    exit 1
fi

GPPPATH=`xcrun -find g++`
if [  $? -ne 0 ]; then
    echo "ERROR: can't find g++ compiler"
    exit 1
fi

MAKEPATH=`xcrun -find make`
if [  $? -ne 0 ]; then
    echo "ERROR: can't find make tool"
    exit 1
fi

TOOLSPATH1=${MAKEPATH%/make}

ARPATH=`xcrun -find ar`
if [  $? -ne 0 ]; then
    echo "ERROR: can't find ar tool"
    exit 1
fi

TOOLSPATH2=${ARPATH%/ar}

export PATH="${TOOLSPATH1}":"${TOOLSPATH2}":/usr/local/bin:$PATH

SDKPATH=`xcodebuild -version -sdk macosx Path`

rm -fR i386 x86_64

echo
echo "***************************************************"
echo "******* Building 64-bit Intel Application *********"
echo "***************************************************"
echo

export CC="${GCCPATH}";export CPP="${GPPPATH}"
export LDFLAGS="-Wl,-syslibroot,${SDKPATH},-arch,x86_64"
export VARIANTFLAGS="-isysroot ${SDKPATH} -arch x86_64 -DMAC_OS_X_VERSION_MAX_ALLOWED=101000 -DMAC_OS_X_VERSION_MIN_REQUIRED=101000 -fvisibility=hidden -fvisibility-inlines-hidden"
export SDKROOT="${SDKPATH}"
export MACOSX_DEPLOYMENT_TARGET=10.10

rm -f *.o
rm -f wrapper
make -f Makefile_mac clean
make -f Makefile_mac all

if [  $? -ne 0 ]; then
    rm -f *.o
    rm -f wrapper
    exit 1
fi

mv -f wrapper wrapper_x86_64

echo
echo "***************************************************"
echo "******* Building arm64 Application *********"
echo "***************************************************"
echo

export CC="${GCCPATH}";export CPP="${GPPPATH}"
export LDFLAGS="-Wl,-syslibroot,${SDKPATH},-arch,arm64"
export VARIANTFLAGS="-isysroot ${SDKPATH} -arch arm64 -DMAC_OS_X_VERSION_MAX_ALLOWED=101000 -DMAC_OS_X_VERSION_MIN_REQUIRED=101000 -fvisibility=hidden -fvisibility-inlines-hidden"
export SDKROOT="${SDKPATH}"
export MACOSX_DEPLOYMENT_TARGET=10.10

rm -f *.o
make -f Makefile_mac clean
make -f Makefile_mac all

if [  $? -ne 0 ]; then
    rm -f *.o
    rm -f wrapper_x86_64
    rm -f wrapper
    exit 1
fi

rm -f *.o

mv -f wrapper wrapper_arm64

lipo -create wrapper_x86_64 wrapper_arm64 -output wrapper
if [ $? -ne 0 ]; then
    rm -f wrapper_x86_64
    rm -f wrapper_arm64
    rm -f wrapper
    exit 1
fi

rm -f wrapper_x86_64
rm -f wrapper_arm64

echo
echo "***************************************************"
echo "**************** Build Succeeded! *****************"
echo "***************************************************"
echo

export CC="";export CXX=""
export LDFLAGS=""
export CPPFLAGS=""
export CFLAGS=""

exit 0

