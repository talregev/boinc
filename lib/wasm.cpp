// This file is part of BOINC.
// http://boinc.berkeley.edu
// Copyright (C) 2026 University of California
//
// BOINC is free software; you can redistribute it and/or modify it
// under the terms of the GNU Lesser General Public License
// as published by the Free Software Foundation,
// either version 3 of the License, or (at your option) any later version.
//
// BOINC is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with BOINC.  If not, see <http://www.gnu.org/licenses/>.

// WebAssembly (Emscripten) build shims.
//
// Emscripten's libc declares ftok() in <sys/ipc.h> but ships no implementation
// (it is part of the SysV IPC API, which the browser sandbox has no equivalent
// for), so referencing code from lib/shmem.cpp, client/app_start.cpp, etc. fails
// to link. BOINC only uses ftok() to derive a stable key from a path, so provide
// a minimal, deterministic implementation matching the POSIX contract.
//
// <sys/ipc.h> declares ftok() inside `extern "C"`; define it with C linkage to
// match, so the emitted symbol is the unmangled `ftok` the callers expect.

#include <sys/ipc.h>
#include <sys/stat.h>

extern "C" key_t ftok(const char *path, int id) {
    struct stat st;
    if (stat(path, &st) < 0) return (key_t)-1;

    return (key_t)((st.st_ino & 0xffff) | ((st.st_dev & 0xff) << 16) | ((id & 0xff) << 24));
}
