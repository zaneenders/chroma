#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SWIFTC=${SWIFTC:-swiftc}
mkdir -p .build/standalone/module-cache Results
"$SWIFTC" -O -whole-module-optimization -D ARENA_STANDALONE \
  -enable-experimental-feature Lifetimes -module-cache-path .build/standalone/module-cache \
  Sources/FrameArena/*.swift Sources/ArenaBenchmarks/main.swift -o .build/standalone/arena-benchmarks
# Timings are intentionally collected without interception overhead.
.build/standalone/arena-benchmarks > Results/timing.csv
if [[ $(uname -s) == Linux ]]; then
  SWIFTC="$SWIFTC" bash Tools/allocation-counter/verify.sh > Results/counter-verification.txt
  LD_PRELOAD="$PWD/Tools/allocation-counter/build/liballocation_counter.so" \
    ARENA_SAMPLES=1 .build/standalone/arena-benchmarks --allocations > Results/allocations.csv
fi
