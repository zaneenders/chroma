#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
SWIFTC="${SWIFTC:-swiftc}"
mkdir -p build
gcc -std=c11 -O2 -Wall -Wextra -Werror -fPIC -shared -fno-builtin \
    allocation_counter.c -ldl -Wl,-z,now -o build/liballocation_counter.so
gcc -std=c11 -O2 -Wall -Wextra -Werror -fno-builtin probe.c -I. \
    -Lbuild -lallocation_counter -pthread -Wl,-rpath,'$ORIGIN' -o build/probe-c
LD_PRELOAD="$PWD/build/liballocation_counter.so" ./build/probe-c
"$SWIFTC" -O -module-cache-path build/module-cache \
    -I . -L build -lallocation_counter -Xlinker -rpath -Xlinker "$PWD/build" \
    probe.swift -o build/probe-swift
LD_PRELOAD="$PWD/build/liballocation_counter.so" ./build/probe-swift
"$SWIFTC" -O -module-cache-path build/module-cache \
    probe-dynamic.swift -o build/probe-dynamic-swift
env -u LD_PRELOAD ./build/probe-dynamic-swift
LD_PRELOAD="$PWD/build/liballocation_counter.so" ./build/probe-dynamic-swift
