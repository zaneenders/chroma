# CPU/headless runtime measurements: first storage pass

These results describe commit `35fe291677ce8613a4d696c1115d1014ab88394d`, before the subsequent construction/interaction simplification. They do not establish the performance of the current rewrite; its comparison is pending.

Measured 2026-10-09 on a shared x86_64 Linux container (AMD EPYC 9V74).
These are CPU/runtime measurements, not native dispatch, backend/GPU, or display measurements.

## Sources and build

- Baseline: `4429069d6097b476078a208968d8ae0beac8be7c`, with only the same headless manifest separation applied locally.
- Candidate source snapshot SHA-256: `1f28f5e041f42aa5ffa7a84df67ade84577a3fd094ace8e3ae407ac2ec92f04d`.
- Snapshot hash is SHA-256 of the sorted `sha256sum` inventory for `Sources` and `Benchmarks/Sources`; manifests, tests and docs are excluded. That first-pass runtime/benchmark source snapshot matched byte-for-byte.
- Swift 6.4 release, identical pinned dependencies, two build jobs, separate source/build directories. No native display libraries installed.
- Measured benchmark and StressFixtures sources match baseline byte-for-byte. No pending PRs were stacked onto the baseline.

```sh
export CHROMA_HEADLESS_ONLY=1
# Use the same Swift 6.4 executable and module-cache paths for both checkouts.
for product in LayoutBenchmark InputBacklogBenchmark; do
  swift build --package-path "$SOURCE/Benchmarks" --scratch-path "$BUILD" \
    --build-system native -c release --jobs 2 --skip-update \
    -Xswiftc -parse-as-library --product "$product"
done
```

`-parse-as-library` accommodates the existing `@main` in `main.swift` benchmark files under the native build system; both sides use it.

## Layout

Existing LayoutBenchmark: 20 rows, six depth/input cases, 3 warmups and 20 measured frames per case.
Run the binary with no arguments and with `--interactive`; repeat each three times, alternating baseline/candidate order.
The table reports medians of the three per-process p50/p95 values (milliseconds). Every run, including allocator runs, matched commands and body counts.

| Nesting | Depth | Input | Base p50 | New p50 | Base p95 | New p95 | p50 change |
|---|---:|---|---:|---:|---:|---:|---:|
| plain | 1 | none | 1.24 | 0.86 | 2.63 | 1.21 | -30.6% |
| plain | 1 | scroll | 2.13 | 1.94 | 4.38 | 4.62 | -9.3% |
| plain | 3 | none | 1.67 | 0.95 | 5.24 | 2.09 | -43.0% |
| plain | 3 | scroll | 2.62 | 1.72 | 4.33 | 2.39 | -34.2% |
| plain | 5 | none | 1.52 | 0.94 | 2.85 | 2.04 | -38.0% |
| plain | 5 | scroll | 2.54 | 3.00 | 4.97 | 5.85 | +18.3% |
| interactive | 1 | none | 2.13 | 1.20 | 4.33 | 1.96 | -43.8% |
| interactive | 1 | scroll | 4.16 | 2.77 | 5.90 | 4.89 | -33.5% |
| interactive | 3 | none | 3.76 | 3.00 | 6.15 | 7.03 | -20.2% |
| interactive | 3 | scroll | 7.02 | 6.23 | 10.27 | 9.15 | -11.3% |
| interactive | 5 | none | 7.91 | 5.91 | 15.03 | 10.59 | -25.3% |
| interactive | 5 | scroll | 13.84 | 9.33 | 23.99 | 14.57 | -32.6% |

The original plain/depth-5/scroll result regressed 18.3%. One focused reverse-order confirmation (candidate first) produced base 2.76/5.23 ms versus new 1.98/2.68 ms p50/p95, with identical output/body counts. The regression did not persist in that check; variability prevents attributing it confidently. The original table is retained, not replaced by the favorable repeat.

Whole-process CPU (median user+system seconds over three runs, including startup/warmups/output): plain 0.560 → 0.317; interactive 1.186 → 1.061. These short runs are noisy and do not establish universal improvement.

## Scheduled input

Run InputBacklogBenchmark with `--events 60 --input-hz 60 --axes 2 --trials 3`, adding:
- Stress: `--workload stress --rows 1000 --depth 3`
- Markdown: `--workload markdown --sections 40`

These modest workloads are smaller than defaults and identical on both sides. Each side applied 360 ordered inputs per workload. The table pools those input samples; process CPU is measured around input application by the existing benchmark.

| Workload | Base CPU p50/p95 ms | New CPU p50/p95 ms | Base wall p50/p95 ms | New wall p50/p95 ms |
|---|---:|---:|---:|---:|
| stress | 16.16/25.85 | 11.20/17.39 | 16.10/25.54 | 11.01/16.94 |
| markdown | 4.60/10.71 | 1.25/2.98 | 4.52/10.01 | 1.22/2.78 |

All trials reached draw coverage for every input and returned to idle. Final draw commands matched: stress 3,626; markdown 2,995. Scheduled draw counts differed (stress base 31/31/33 vs new 30/30/31; markdown base 36/36/36 vs new 53/54/54), so whole-run work was not identical presentation-for-presentation.

## Allocation requests

Separate single process runs per Layout mode used the [small glibc LD_PRELOAD counter](Tools/allocation-counts.c) for `malloc`, `calloc`, `realloc`, `memalign`, `aligned_alloc`, and `posix_memalign`. All six APIs passed a known 6-call/856-byte smoke test. Instrumented timings are excluded above. Build it with `cc -O2 -shared -fPIC -o allocation-counts.so Benchmarks/Tools/allocation-counts.c`, then run each benchmark with `LD_PRELOAD="$PWD/allocation-counts.so"`, capturing stderr separately.

| Layout mode | Base calls | New calls | Change | Base requested bytes | New requested bytes |
|---|---:|---:|---:|---:|---:|
| plain | 895,625 | 587,152 | -34.4% | 266,200,970 | 206,760,776 |
| interactive | 2,570,128 | 1,842,642 | -28.3% | 1,003,717,230 | 856,788,282 |

These are actual intercepted allocator API requests, not capacity-growth counters. Counts cover startup, fonts, warmups, all fixed frames, and output. Requested bytes include realloc requests; they are neither live nor peak memory. Custom allocators, direct mmap, and un-intercepted libc internals are outside coverage. One instrumented process per mode/side is not an allocation distribution.

All timing and allocation runs followed completed builds/tests in a reserved idle window. The shared container remains a limitation. Baseline/candidate benchmark output parity is checked; no native frame-rate claim follows from these results.

Production Swift source volume increased: Chroma 6,815 → 7,188 lines, ChromaMarkdown 531 → 576 (+418 combined). These measurements do not support a fewer-lines claim.
