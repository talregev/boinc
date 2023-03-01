#!/bin/bash

# This file is part of BOINC.
# http://boinc.berkeley.edu
# Copyright (C) 2021 University of California
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
## This file contains the names and download URLs for the 7 third-party
## libraries needed for building BOINC for Macintosh computers.
##
## This file is usually source'ed by scripts that build the dependencies.
##
## Update this file and the Xcode project build settings when upgrading
## to a newer version of one of these libraries.
##
## ** NOTE ** the scripts buildc-ares.sh, buildcurl.sh, buildopenssl.sh
## and buildWxMac.sh contain code to patch source files for their
## respective libraries, so they may need to be modified for new versions
## of those source files.
##
## To ensure that rebuilds of older versions of BOINC always use the
## same versions of the third party libraries as the original builds,
## always hard-code the path to the correct libraries in the Xcode build
## settings; please do NOT include or reference this file in the Xcode
## build settings.
##

opensslDirName="openssl-3.0.0"
opensslFileName="openssl-3.0.0.tar.gz"
opensslURL="https://www.openssl.org/source/openssl-3.0.0.tar.gz"

caresDirName="c-ares-1.17.2"
caresFileName="c-ares-1.17.2.tar.gz"
caresURL="https://c-ares.org/download/c-ares-1.17.2.tar.gz"

curlDirName="curl-7.79.1"
curlFileName="curl-7.79.1.tar.gz"
curlURL="https://curl.se/download/curl-7.79.1.tar.gz"

wxWidgetsDirName="wxWidgets-3.1.5"
wxWidgetsFileName="wxWidgets-3.1.5.tar.bz2"
wxWidgetsURL="https://github.com/wxWidgets/wxWidgets/releases/download/v3.1.5/wxWidgets-3.1.5.tar.bz2"

freetypeDirName="freetype-2.11.0"
freetypeFileName="freetype-2.11.0.tar.gz"
freetypeURL="https://download.savannah.gnu.org/releases/freetype/freetype-2.11.0.tar.gz"

ftglDirName="ftgl-2.1.3~rc5"
ftglFileName="ftgl-2.1.3-rc5.tar.gz"
ftglURL="https://sourceforge.net/projects/ftgl/files/FTGL%20Source/2.1.3%7Erc5/ftgl-2.1.3-rc5.tar.gz"

nghttp2DirName="nghttp2-1.52.0"
nghttp2FileName="nghttp2-1.52.0.tar.gz"
nghttp2URL="https://github.com/nghttp2/nghttp2/releases/download/v1.52.0/nghttp2-1.52.0.tar.gz"

return 0
