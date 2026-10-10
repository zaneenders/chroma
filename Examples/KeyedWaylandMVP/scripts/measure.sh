#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SWIFT=${SWIFT:-swift}
"$SWIFT" build -c release
BIN=$("$SWIFT" build -c release --show-bin-path)/keyed-demo
mkdir -p Results .build/counter
for mode in --benchmark-core --benchmark; do
    for trial in 1 2 3 4 5; do "$BIN" "$mode" --frames 10000; done
done | tee Results/timing.txt
if [[ $(uname -s) == Linux ]]; then
    cc -shared -fPIC -O2 -fno-builtin -pthread Vendor/FrameArena/Tools/allocation-counter/allocation_counter.c -ldl -o .build/counter/liballocation_counter.so
    for mode in --benchmark-core --benchmark; do
        LD_PRELOAD="$PWD/.build/counter/liballocation_counter.so" "$BIN" "$mode" --frames 10000
    done | tee Results/allocations.txt
fi
