# CPU/headless runtime measurements: direct-only rewrite

Measured 2026-10-09 in a shared x86_64 Linux container reporting Intel Xeon Platinum 8573C. Compare only this matched baseline/candidate run; earlier results used a different environment. CPU/headless measurements do not establish native/GPU/display performance.

## Exact source and build

- Baseline: `4429069d6097b476078a208968d8ae0beac8be7c`; only the same headless manifest separation was applied locally. No other PRs were stacked onto it.
- Built candidate: `cf54d745cbe14f62e982e3cce6dc982f53acf5c2`. Its runtime/benchmark sources exactly match tested head `050f75abcdc03f855bd96763e8b66f449cab309b`, tree `78b9410711d8cb83ca08432ccec4206e31abe1ef`, before and after measurement.
- Baseline source fingerprint: `2888e5e885748c98c5d0f265aabe047609afa04d2bd97dedaaa231fd640ca929`.
- Candidate source fingerprint: `47ccbafe058857c7df6117b9018390ca90744cbec93728d025b91047c522bd05`.
- Fingerprints hash the sorted `sha256sum` inventory for every file under `Sources` and `Benchmarks/Sources`; manifests, tests and docs are excluded.
- Swift 6.4 release, identical pinned dependencies, separate source/build directories, two build jobs. All builds/tests ended before timing. No native display libraries were installed.

```sh
export CHROMA_HEADLESS_ONLY=1
# Use the same Swift 6.4 executable and module-cache paths for each checkout.
for product in LayoutBenchmark InputBacklogBenchmark; do
  swift build --package-path "$SOURCE/Benchmarks" --scratch-path "$BUILD" \
    --build-system native -c release --jobs 2 --skip-update \
    -Xswiftc -parse-as-library --product "$product"
done
```

The identical `-parse-as-library` flag handles the existing benchmark `@main`/`main.swift` naming under the native build system. Run each built variant with:

```sh
BIN="$BUILD/x86_64-unknown-linux-gnu/release"
"$BIN/LayoutBenchmark"
"$BIN/LayoutBenchmark" --interactive
"$BIN/InputBacklogBenchmark" --events 60 --input-hz 60 --axes 2 --trials 3 --workload stress --rows 1000 --depth 3
"$BIN/InputBacklogBenchmark" --events 60 --input-hz 60 --axes 2 --trials 3 --workload markdown --sections 40
```


## Workload comparability

The candidate fixtures use direct `LayoutBuffer` functions instead of Block/result-builder descriptors. Source review preserved scene text, dimensions, nested layers, events, frame counts and timing boundaries. Both sides create the MarkdownText value once before warmup. Layout passes an explicit InputState in every measured frame, so the new no-argument snapshot behavior does not omit its input applications.

Command counts match in every timed and instrumented layout case and at the end of every input trial. This is command-count parity only; these benchmarks did not compare DrawList bytes or complete geometry.

## Layout: all 12 cases

Each process runs six cases with 20 rows, 3 warmup frames and 20 measured frames per case. Three process runs per variant/mode used order B-plain, B-interactive, C-plain, C-interactive; then C-plain, C-interactive, B-plain, B-interactive; then the first order again. B is baseline, C is candidate.

Table values are milliseconds: medians of the three per-process p50/p95 values, with min–max of the three p50 values. [Compact raw results](RUNTIME_RESULTS.json) preserve all p50/p95 samples and exact process order/CPU times.

| Nesting | Depth | Input | Base p50 / p95 | New p50 / p95 | Base p50 range | New p50 range |
|---|---:|---|---:|---:|---:|---:|
| plain | 1 | none | 3.60 / 5.71 | 1.34 / 5.49 | 2.00–5.60 | 0.60–2.09 |
| plain | 1 | scroll | 7.44 / 13.17 | 4.10 / 8.80 | 3.92–9.36 | 3.09–5.02 |
| plain | 3 | none | 4.04 / 7.09 | 2.47 / 13.29 | 2.64–8.28 | 2.43–3.79 |
| plain | 3 | scroll | 7.68 / 13.37 | 5.24 / 13.32 | 7.35–10.48 | 4.94–5.44 |
| plain | 5 | none | 5.73 / 14.84 | 1.79 / 4.56 | 4.73–6.18 | 1.69–2.31 |
| plain | 5 | scroll | 11.16 / 24.80 | 3.06 / 7.30 | 5.34–11.95 | 2.67–4.62 |
| interactive | 1 | none | 4.09 / 9.42 | 2.12 / 3.79 | 3.27–7.06 | 1.68–4.40 |
| interactive | 1 | scroll | 8.90 / 37.39 | 3.10 / 5.78 | 8.47–11.58 | 2.89–4.38 |
| interactive | 3 | none | 9.21 / 16.71 | 2.82 / 6.91 | 7.87–10.78 | 1.58–3.08 |
| interactive | 3 | scroll | 19.59 / 30.88 | 3.66 / 7.10 | 16.24–37.02 | 3.27–5.09 |
| interactive | 5 | none | 19.34 / 43.64 | 2.17 / 4.07 | 11.97–30.23 | 1.16–3.40 |
| interactive | 5 | scroll | 43.78 / 106.43 | 5.37 / 12.74 | 43.03–46.12 | 4.54–6.06 |

All sampled p50 medians decreased, but plain depth-3/no-scroll p95 regressed from 7.09 to 13.29 ms. Per-process ranges show substantial variability. The original result is retained. One bounded reverse-order confirmation (candidate first) gave baseline 2.56/5.74 ms versus candidate 1.32/4.00 ms p50/p95, with 315 commands and 20 construction entries/frame on both sides. The tail regression did not recur in that check; this variability does not prove universal speed or tail-latency improvement. No tuning was performed.

The JSON field `bodiesPerFrame` counts baseline Row.body evaluations and candidate direct row-function emissions. These are corresponding construction entries, not identical runtime operations. No-scroll/scroll counts were:
- Plain at every depth: 20/40 → 20/40
- Interactive depth 1: 40/80 → 40/80
- Interactive depth 3: 80/160 → 40/80
- Interactive depth 5: 120/240 → 40/80

Whole-process user+system CPU (median seconds over three runs, including startup/warmups/output): plain 1.480 → 1.020; interactive 4.022 → 0.633. Instrumented timing is excluded.

## Scheduled input

InputBacklogBenchmark used `--events 60 --input-hz 60 --axes 2 --trials 3`, plus `--workload stress --rows 1000 --depth 3` or `--workload markdown --sections 40`. These bounded workloads are smaller than defaults and identical on both sides. CPU is the existing process-clock measurement around input application; p50/p95 pool 360 ordered applications per side/workload.

| Workload | Base CPU p50/p95 ms | New CPU p50/p95 ms | Base wall p50/p95 ms | New wall p50/p95 ms |
|---|---:|---:|---:|---:|
| stress | 21.63/45.62 | 10.16/22.07 | 21.47/45.61 | 9.95/21.49 |
| markdown | 8.16/25.93 | 1.27/3.58 | 7.89/23.30 | 1.20/3.30 |

All 12 trials (two workloads × two variants × three trials) applied 120 inputs in order, had zero uncovered inputs, and established idle. Final commands matched: stress 3,626; markdown 2,995. Scheduled draw counts differed: stress B 32/31/31 vs C 31/30/31; markdown B 30/32/31 vs C 52/50/52. Whole runs therefore did not execute identical numbers of presentations.

## Actual allocation requests

Separate single-process passes per Layout mode used the [six-API glibc counter](Tools/allocation-counts.c): malloc, calloc, realloc, memalign, aligned_alloc and posix_memalign. All six APIs passed the known 6-call/856-byte smoke test. Each instrumented output matched its variant’s uninstrumented command and construction-counter counts; cross-variant construction differences remain as reported above. Compile with `cc -O2 -shared -fPIC -o allocation-counts.so Benchmarks/Tools/allocation-counts.c`; run each binary with `LD_PRELOAD="$PWD/allocation-counts.so"`, keeping stderr separate.

| Layout | Base requests | New requests | Change | Base requested bytes | New requested bytes |
|---|---:|---:|---:|---:|---:|
| plain | 895,593 | 154,955 | -82.7% | 266,200,931 | 75,579,486 |
| interactive | 2,570,140 | 177,405 | -93.1% | 1,003,716,509 | 126,258,844 |

These count intercepted allocator requests, including process startup, fonts, warmups, fixed frames and output; they are not capacity-growth counters. Requested bytes include realloc requests and are neither live nor peak memory. Custom allocators, direct mmap and un-intercepted libc internals are outside coverage. One instrumented process per mode/side is not an allocation distribution.

Core + Markdown Swift source volume: 7,346 → 7,220 lines (−126); 86 → 67 files. Chroma is 6,815 → 6,634 lines; Markdown is 531 → 586. This count excludes tests, benchmarks and other modules.
