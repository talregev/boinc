# This file is part of BOINC.
# https://boinc.berkeley.edu
# Copyright (C) 2026 University of California
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

include(${CMAKE_CURRENT_LIST_DIR}/../../vcpkg_root_find.cmake)
include(${VCPKG_ROOT}/triplets/community/wasm32-emscripten.cmake)

set(VCPKG_BUILD_TYPE release)

# The wasm client is a -pthread (shared-memory) build because WasmFS's OPFS backend runs on a
# dedicated thread. Every linked library must share that ABI, so build the emscripten deps
# (curl/openssl/zlib) with -pthread too; otherwise the client link fails against non-shared-memory
# objects. (See wasm/ci_configure_client.sh + client/main.cpp OPFS mount.)
set(VCPKG_C_FLAGS "-pthread")
set(VCPKG_CXX_FLAGS "-pthread")
