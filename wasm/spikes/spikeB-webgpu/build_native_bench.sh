#!/bin/bash
# Build the committed native xorshift32 benchmark (the reproducible "CPU - native" baseline).
set -e
cd "$(dirname "$0")"
cc -O2 -pthread native_bench.c -o native_bench
echo "built ./native_bench  —  run: ./native_bench [nthreads]"
