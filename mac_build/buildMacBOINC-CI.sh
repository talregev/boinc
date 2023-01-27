#!/bin/bash

# This file is part of BOINC.
# http://boinc.berkeley.edu
# Copyright (C) 2022 University of California
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
# Script to build the different targets in the BOINC xcode project using a
# combined install directory for all dependencies
#
# Usage:
# ./mac_build/buildMacBOINC-CI.sh [--cache_dir PATH] [--debug] [--clean] [--no_shared_headers]
#
# --cache_dir is the path where the dependencies are installed by 3rdParty/buildMacDependencies.sh.
# --debug will build the debug Manager (needs debug wxWidgets library in cache_dir).
# --clean will force a full rebuild.
# --no_shared_headers will build targets individually instead of in one call of BuildMacBOINC.sh (NOT recommended)

# check working directory because the script needs to be called like: ./mac_build/buildMacBOINC-CI.sh
set -e

if [ ! -d "mac_build" ]; then
    echo "start this script in the source root directory"
    exit 1
fi

# Delete any obsolete paths to old build products
rm -fR ./zip/build
rm -fR ./mac_build/build

cache_dir="$(pwd)/3rdParty/buildCache/mac"
style="Deployment"
config=""
doclean=""
beautifier="cat" # we need a fallback if xcpretty is not available
share_paths="yes"
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -clean|--clean)
        doclean="yes"
        ;;
        --cache_dir)
        cache_dir="$2"
        shift
        ;;
        --debug|-dev)
        style="Development"
        config="-dev"
        ;;
        --no_shared_headers)
        share_paths="no"
        ;;
    esac
    shift # past argument or value
done

if [ ! -d "$cache_dir" ] || [ ! -d "$cache_dir/lib" ] || [ ! -d "$cache_dir/include" ]; then
    echo "${cache_dir} is not a directory or does not contain dependencies"
fi

XCPRETTYPATH=`xcrun -find xcpretty 2>/dev/null`
if [ $? -eq 0 ]; then
    beautifier="xcpretty"
fi

cd ./mac_build || exit 1
retval=0

if [ ${share_paths} = "yes" ]; then
    ## all targets share the same header and library search paths
    libSearchPathDbg=""
    if [ "${style}" == "Development" ]; then
        libSearchPathDbg="./build/Development  ${cache_dir}/lib/debug"
    fi
    source BuildMacBOINC.sh ${config} -all -setting HEADER_SEARCH_PATHS "../clientgui ${cache_dir}/include ../samples/jpeglib ${cache_dir}/include/freetype2" -setting USER_HEADER_SEARCH_PATHS "" -setting LIBRARY_SEARCH_PATHS "$libSearchPathDbg ${cache_dir}/lib ../lib" | tee xcodebuild_all.log | $beautifier; retval=${PIPESTATUS[0]}
    if [ $retval -ne 0 ]; then
        cd ..; exit 1; fi
    return 0
fi

## This is code that builds each target individually in case the above shared header paths version is giving problems
## Note: currently this does not build the boinc_zip library
if [ "${doclean}" = "yes" ]; then
    ## clean all targets
    xcodebuild -project boinc.xcodeproj -target Build_All  -configuration ${style} clean | $beautifier; retval=${PIPESTATUS[0]}
    if [ $retval -ne 0 ]; then cd ..; exit 1; fi

    ## clean boinc_zip which is not included in Build_All
    xcodebuild -project ../zip/boinc_zip.xcodeproj -target boinc_zip -configuration ${style} clean | $beautifier; retval=${PIPESTATUS[0]}
    if [ $retval -ne 0 ]; then cd ..; exit 1; fi
fi

## Target mgr_boinc also builds dependent targets SetVersion and BOINC_Client
libSearchPathDbg=""
if [ "${style}" == "Development" ]; then
    libSearchPathDbg="${cache_dir}/lib/debug"
fi
target="mgr_boinc"
echo "Building ${target}..."
source BuildMacBOINC.sh ${config} -noclean -target ${target} -setting HEADER_SEARCH_PATHS "../clientgui ${cache_dir}/include" -setting LIBRARY_SEARCH_PATHS "${libSearchPathDbg} ${cache_dir}/lib" | tee xcodebuild_${target}.log | $beautifier; retval=${PIPESTATUS[0]}
if [ ${retval} -ne 0 ]; then
    echo "Building ${target}...failed"
    cd ..; exit 1;
fi
echo "Building ${target}...done"

## Target gfx2libboinc also build dependent target jpeg
target="gfx2libboinc"
echo "Building ${target}..."
source BuildMacBOINC.sh ${config} -noclean -target ${target} -setting HEADER_SEARCH_PATHS "../samples/jpeglib" | tee xcodebuild_${target}.log | $beautifier; retval=${PIPESTATUS[0]}
if [ ${retval} -ne 0 ]; then
    echo "Building ${target}...failed"
    cd ..; exit 1;
fi
echo "Building ${target}...done"

target="libboinc"
echo "Building ${target}..."
source BuildMacBOINC.sh ${config} -noclean -target ${target} | tee xcodebuild_${target}.log | $beautifier; retval=${PIPESTATUS[0]}
if [ ${retval} -ne 0 ]; then
    echo "Building ${target}...failed"
    cd ..; exit 1;
fi
echo "Building ${target}...done"

target="api_libboinc"
echo "Building ${target}..."
source BuildMacBOINC.sh ${config} -noclean -target ${target} | tee xcodebuild_${target}.log | $beautifier; retval=${PIPESTATUS[0]}
if [ ${retval} -ne 0 ]; then
    echo "Building ${target}...failed"
    cd ..; exit 1;
fi
echo "Building ${target}...done"

target="PostInstall"
echo "Building ${target}..."
source BuildMacBOINC.sh ${config} -noclean -target ${target} | tee xcodebuild_${target}.log | $beautifier; retval=${PIPESTATUS[0]}
if [ ${retval} -ne 0 ]; then
    echo "Building ${target}...failed"
    cd ..; exit 1;
fi
echo "Building ${target}...done"

target="switcher"
echo "Building ${target}..."
source BuildMacBOINC.sh ${config} -noclean -target ${target} | tee xcodebuild_${target}.log | $beautifier; retval=${PIPESTATUS[0]}
if [ ${retval} -ne 0 ]; then
    echo "Building ${target}...failed"
    cd ..; exit 1;
fi
echo "Building ${target}...done"

target="gfx_switcher"
echo "Building ${target}..."
source BuildMacBOINC.sh ${config} -noclean -target ${target} | tee xcodebuild_${target}.log | $beautifier; retval=${PIPESTATUS[0]}
if [ ${retval} -ne 0 ]; then
    echo "Building ${target}...failed"
    cd ..; exit 1;
fi
echo "Building ${target}...done"

target="Install_BOINC"
echo "Building ${target}..."
source BuildMacBOINC.sh ${config} -noclean -target ${target} | tee xcodebuild_${target}.log | $beautifier; retval=${PIPESTATUS[0]}
if [ ${retval} -ne 0 ]; then
    echo "Building ${target}...failed"
    cd ..; exit 1;
fi
echo "Building ${target}...done"

libSearchPath=""
if [ "${style}" == "Development" ]; then
   libSearchPath="./build/Development"
fi
target="ss_app"
echo "Building ${target}..."
source BuildMacBOINC.sh ${config} -noclean -target ${target} -setting HEADER_SEARCH_PATHS "../api/ ../samples/jpeglib/ ${cache_dir}/include ${cache_dir}/include/freetype2"  -setting LIBRARY_SEARCH_PATHS "${libSearchPath} ${cache_dir}/lib ../lib" | tee xcodebuild_${target}.log | $beautifier; retval=${PIPESTATUS[0]}
if [ ${retval} -ne 0 ]; then
    echo "Building ${target}...failed"
    cd ..; exit 1;
fi
echo "Building ${target}...done"

target="ScreenSaver"
echo "Building ${target}..."
source BuildMacBOINC.sh ${config} -noclean -target ${target} -setting GCC_ENABLE_OBJC_GC "unsupported" | tee xcodebuild_${target}.log | $beautifier; retval=${PIPESTATUS[0]}
if [ ${retval} -ne 0 ]; then
    echo "Building ${target}...failed"
    cd ..; exit 1;
fi
echo "Building ${target}...done"

target="boinc_opencl"
echo "Building ${target}..."
source BuildMacBOINC.sh ${config} -noclean -target ${target} | tee xcodebuild_${target}.log | $beautifier; retval=${PIPESTATUS[0]}
if [ ${retval} -ne 0 ]; then
    echo "Building ${target}...failed"
    cd ..; exit 1;
fi
echo "Building ${target}...done"

target="setprojectgrp"
echo "Building ${target}..."
source BuildMacBOINC.sh ${config} -noclean -target ${target} | tee xcodebuild_${target}.log | $beautifier; retval=${PIPESTATUS[0]}
if [ ${retval} -ne 0 ]; then
    echo "Building ${target}...failed"
    cd ..; exit 1;
fi
echo "Building ${target}...done"

target="cmd_boinc"
echo "Building ${target}..."
source BuildMacBOINC.sh ${config} -noclean -target ${target} | tee xcodebuild_${target}.log | $beautifier; retval=${PIPESTATUS[0]}
if [ ${retval} -ne 0 ]; then
    echo "Building ${target}...failed"
    cd ..; exit 1;
fi
echo "Building ${target}...done"

target="Uninstaller"
echo "Building ${target}..."
source BuildMacBOINC.sh ${config} -noclean -target ${target} | tee xcodebuild_${target}.log | $beautifier; retval=${PIPESTATUS[0]}
if [ ${retval} -ne 0 ]; then
    echo "Building ${target}...failed"
    cd ..; exit 1;
fi
echo "Building ${target}...done"

target="SetUpSecurity"
echo "Building ${target}..."
source BuildMacBOINC.sh ${config} -noclean -target ${target} | tee xcodebuild_${target}.log | $beautifier; retval=${PIPESTATUS[0]}
if [ ${retval} -ne 0 ]; then
    echo "Building ${target}...failed"
    cd ..; exit 1;
fi
echo "Building ${target}...done"

target="AddRemoveUser"
echo "Building ${target}..."
source BuildMacBOINC.sh ${config} -noclean -target ${target} | tee xcodebuild_${target}.log | $beautifier; retval=${PIPESTATUS[0]}
if [ ${retval} -ne 0 ]; then
    echo "Building ${target}...failed"
    cd ..; exit 1;
fi
echo "Building ${target}...done"

cd ..

echo "Testing libs and binaries for univaral build."
echo ""

binaries_libs_list="*.a boinc switcher gfx_switcher boincscr setprojectgrp boinccmd SetUpSecurity AddRemoveUser BOINCManager PostInstall BOINCSaver *Installer Uninstall*"
folders_list="3rdParty/buildCache/mac/lib mac_build/build/Deployment"

for object in $binaries_libs_list; do
    echo "Search for: $object"
    found_list=$(find $folders_list -type f -name "$object")
    if [ -z "$found_list" ]; then
        echo "ERROR: $object not found"
        exit 1
    fi
    find $folders_list -type f -name "$object" -exec sh -c '
    for f do
        echo "Test : $f"
        if ! lipo "$f" -verify_arch x86_64 arm64; then
            echo "Fail: $(basename $f) is not universal"
            lipo -info "$f"
            exit 1
        fi         
    done
    ' sh {} +; 
done
