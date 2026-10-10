# Measured results

Swift 6.4 RELEASE, x86_64 Linux (Debian 13), Intel Xeon Platinum 8573C, shared execution environment; no CPU affinity or frequency isolation. Recorded 2026-10-09.

## CPU time

Median process CPU ns per appended-and-read record; bracketed range is min–max across nine samples. These are noisy shared-machine measurements, not a statistical speedup claim.

| Storage | Warm numeric | Fresh reserved | Fresh growing |
|---|---:|---:|---:|
| array | 6.227 [4.833–7.077] | 6.363 [4.957–9.135] | 20.443 [6.012–28.019] |
| unique | 5.001 [3.992–7.753] | 4.524 [3.934–5.957] | 36.625 [23.242–52.588] |
| arena | 4.867 [3.881–7.778] | 4.686 [3.922–5.731] | 36.701 [28.382–47.951] |
| slab | 5.027 [4.205–6.560] | 4.577 [3.757–5.871] | not supported |

Each numeric sample performs 4,194,304 record writes plus reads. All 32-byte records have seven fields consumed into an identical checksum. Warm medians: UniqueArray 5.001 ns, wrapper 4.867 ns, slab 5.027 ns. The overlapping ranges do not establish a useful slab CPU advantage.

The warm payload benchmark constructs 32,768 long-String/reference/capturing-closure payloads per sample. Median CPU cost is 1,377.741 ns/payload for UniqueArray and 1,356.091 ns/payload for FrameArena. These also have overlapping ranges.

## Intercepted allocation calls

| Workload | Array | UniqueArray | FrameArena | Slab |
|---|---:|---:|---:|---:|
| Warm numeric, 1,024 frames | 0 | 0 | 0 | 0 |
| Fresh reserved, 1,024 frames | 1,024 | 1,024 | 1,024 | 1,024 |
| Fresh growing, 1,024 frames | 13,312 | 21,504 | 21,504 | unsupported |
| Warm payload, 128 × 256 | not run | 98,304 | 98,304 | type rejected |

Fresh reserved Array calls malloc; the other three call posix_memalign. Warm payloads make three observed malloc calls per element in this optimized workload, despite zero backing-capacity growth, and all 98,304 are matched by measured free calls. This does not identify each call with a particular language construct: optimizer/runtime allocation combining can change the count.

Array fresh-growing capacity changes total 12,288 while intercepted malloc calls total 13,312. This deliberately illustrates why capacity-growth metrics must not be labeled malloc counts. The fresh-buffer baseline includes clearing the initially empty array; implementation allocations need not change reported capacity.

The counter is scoped to the calling thread and outermost intercepted public allocator entries; it does not cover hidden/direct allocator routes or OS mappings. The last backing-buffer free is outside the measured fresh-buffer region, so reserved loops report 1,023 measured frees. Timing CSV is collected without preload; do not use CPU columns from allocation CSV as benchmark timings.

## Verification

- Runtime: 7 passed.
- Compile-fail: 12 expected rejections, plus positive control passed.
- Trap tests: 7 expected traps with diagnostic matching.
- AddressSanitizer: 7 runtime tests passed with leak detection disabled.
- LeakSanitizer: unavailable here; its process-inspection/ptrace error is retained in tests-asan.txt. No leak-sanitizer pass is claimed.
- Independent safety/benchmark review: no practical allocator safety issue found; review-driven construction-order/script/rotation fixes applied. Optimized-code review confirmed stored record fields remain consumed.

## Commands

```sh
export SWIFTC=/workspace/shared/swift-setup/toolchains/6.4.0/usr/bin/swiftc
export SWIFT=/workspace/shared/swift-setup/toolchains/6.4.0/usr/bin/swift
export SWIFTPM_MODULECACHE_OVERRIDE=/tmp/arena-module-cache
export CLANG_MODULE_CACHE_PATH=/tmp/arena-module-cache
$SWIFT test -Xswiftc -module-cache-path -Xswiftc /tmp/arena-module-cache
bash Tools/compile-fail.sh
bash Tools/trap-tests.sh
ASAN_OPTIONS=detect_leaks=0 $SWIFT test --sanitize address --scratch-path .build/asan -Xswiftc -module-cache-path -Xswiftc /tmp/arena-module-cache
bash Tools/benchmark.sh
```

The toolchain paths above record this run, not a required installation location. Set SWIFTC/SWIFT to your Swift 6.4 installation. The benchmark script records nine uninstrumented samples plus one separate instrumented run, verifies the counter with C and Swift positive controls, and emits raw CSVs.

## Tested source hashes

```text
44821c680008cd745fa1a39ac0d24334003828e379c5487f6063475a99be3df2  Sources/ArenaBenchmarks/main.swift
5c39a05999c932df0564a05a90fae35b84c5f2166fd3f347987c319073c692a4  Sources/FrameArena/FrameArena.swift
cfa5b244c165414850af8b95726c34cb3d57b1d887b40dae5441d3ef148bea15  Sources/FrameArena/TrivialSlab.swift
```
