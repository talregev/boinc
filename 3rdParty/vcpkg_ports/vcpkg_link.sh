#!/bin/sh

if [ -z "${BASH_SOURCE}" ]; then
    SCRIPT_PATH=$(dirname -- "$0")
else
    SCRIPT_PATH=$(dirname -- "${BASH_SOURCE[0]}")
fi

export VCPKG_LINK=$(cat $SCRIPT_PATH/vcpkg_link.txt)
echo $VCPKG_LINK
