# Structural-path experiment, 2026-10-09

## Scope and provenance

Issue #116, following #103. Baseline production code is `7d9012c`; candidate code
is the implementation in this change (local tested commit `903c221`). Both use **identical fixture-version-2 benchmark sources**, including
plain/identified selection and per-phase CPU clocks. This matters: the fixture's
new conditional adds a branch segment and its header text changed, so comparing
with an untouched version-1 executable would mix workload and implementation.

Linux x86_64, Intel Xeon Platinum 8573C cloud host; Swift 6.4 release with symbols
(`-c release -Xswiftc -g`, builds limited to `-j 2`). Other Chroma builds and
benchmarks were stopped for the final serial timing matrix. Shared-host noise
still applies. These are HeadlessHost CPU/layout/input measurements, without
native dispatch, compositor scheduling, GPU work or physical-display latency.

Executable SHA256:

- Baseline: `9f12ba8b4845691b442a27264d9505316fcbab287c2b38ca68db60121ae8eb86`
- Candidate: `7990709ea543bb5417494862ee986895f84c761734aa82e02d61ba8c3c9485bd`

## Why this representation

First remove one-element temporary scope arrays and the redundant prefix
concatenation caused by searching a ScopedBlock for a collection before unwrapping
it. A single-scope-array-only experiment saved about 3.4% of malloc calls in the
plain depth-8 allocation replay, but less than 1% of requested bytes. Large
ancestor-array copies remained.

A prefix-sharing prototype removed those copies but added overhead for shallow
paths. The final implementation keeps up to 32 segments contiguous and shares
immutable suffix nodes after that. Batch extension follows the same boundary as
single extension. Nodes own identity values only, with no global interning table,
resolved subtree, callback or geometry cache. A cached fingerprint accelerates
hashing and rejection; exact segment comparison remains authoritative. Optimized
x86_64 Swift 6.4 assembly lowers the recursive comparison to a loop without
per-ancestor retain/release calls.

32 is a private measured tradeoff, not a promise of a universally optimal cutoff.
Fresh event registrations, distinct idle/current preparations, focus contexts,
hover reuse and paint/observation boundaries are unchanged. Collection ID scans
are unchanged and remain separate #93 work.

## Release timing matrix

Three trials per case, each with 10 measured cycles after three warmups; baseline
and candidate order alternated, with no probes loaded. Each cell is the median
across trials of p50 / p95, in milliseconds. An input burst contains **14 ordered
actionable events** (two activations and 12 scroll events), not a single event.
Presentation is one coalesced frame. Each trial uses lower-median p50 and nearest-
rank p95; with only 10 samples the latter is the largest sample, so tails are noisy.
[Raw trial values](Timings.csv) include both clocks and drawing-command counts.

### Elapsed wall time

| Fixture | Baseline input | Candidate input | Baseline presentation | Candidate presentation |
| --- | ---: | ---: | ---: | ---: |
| plain / depth 0 | 46.04 / 60.50 | 42.95 / 66.79 | 3.97 / 5.19 | 4.01 / 9.13 |
| identified / depth 0 | 116.46 / 144.39 | 120.82 / 158.86 | 9.72 / 13.77 | 9.64 / 13.64 |
| plain / depth 8 | 555.20 / 732.60 | 454.11 / 604.23 | 37.63 / 55.60 | 34.56 / 58.54 |
| identified / depth 8 | 698.48 / 919.96 | 468.29 / 540.58 | 46.91 / 62.20 | 33.65 / 48.23 |
| plain / depth 16 | 2244.63 / 3386.60 | 1687.14 / 2157.84 | 154.38 / 268.96 | 116.82 / 165.42 |
| identified / depth 16 | 2513.80 / 3614.17 | 1525.29 / 2183.20 | 172.48 / 268.93 | 102.68 / 182.07 |

### Process CPU time

| Fixture | Baseline input | Candidate input | Baseline presentation | Candidate presentation |
| --- | ---: | ---: | ---: | ---: |
| plain / depth 0 | 46.04 / 57.32 | 42.96 / 66.80 | 3.97 / 5.19 | 4.02 / 9.13 |
| identified / depth 0 | 116.46 / 144.39 | 120.70 / 158.76 | 9.72 / 13.78 | 9.64 / 13.64 |
| plain / depth 8 | 555.19 / 732.15 | 454.07 / 604.21 | 37.62 / 55.61 | 34.56 / 58.55 |
| identified / depth 8 | 698.49 / 919.54 | 468.29 / 540.58 | 46.91 / 62.21 | 33.66 / 48.24 |
| plain / depth 16 | 2243.63 / 3386.12 | 1686.81 / 2157.60 | 154.37 / 268.97 | 116.82 / 165.27 |
| identified / depth 16 | 2513.76 / 3613.94 | 1525.28 / 2182.86 | 172.47 / 268.93 | 102.66 / 182.09 |

The median depth-8 input burst falls 18.2% (plain) and 33.0% (identified); depth-16
falls 24.8% and 39.3%. Shallow median input is −6.7% plain and +3.8% identified,
and shallow median presentation is essentially flat. Individual trials vary
substantially: plain depth-8 candidate input p50 ranges 443.5–680.1 ms versus
539.0–665.6 ms baseline. This is not a uniform per-trial speedup or a confidence
interval. The shallow plain presentation p95 increased 5.19→9.13 ms in this small
sample matrix; the additional check below preserves that uncertainty rather than
claiming all tails improved.


### Additional shallow check

Three further alternating trials at depth 0 used **30 measured cycles** after
three warmups, with the same binaries, no probes, and no other Chroma jobs.
All six pairs again matched commands and deterministic work. Median trial wall
p50 / p95 values in milliseconds ([all trial clocks](ShallowTimings.csv)):

| Fixture | Baseline input | Candidate input | Baseline presentation | Candidate presentation |
| --- | ---: | ---: | ---: | ---: |
| plain / depth 0 | 41.48 / 68.94 | 41.34 / 53.13 | 3.87 / 7.03 | 3.76 / 8.27 |
| identified / depth 0 | 124.76 / 245.80 | 111.68 / 123.24 | 10.02 / 24.31 | 9.01 / 11.58 |

Shallow median cost remains broadly comparable, but the plain presentation tail
is still mixed: individual trial p95 values are 7.03→8.27, 8.06→21.07 and
6.63→4.88 ms. This shared-host experiment does **not** establish non-regression
of every shallow tail. The draft retains this limitation for review; the evidence
supports reduced deep-path copying and aggregate input cost, not a universal
latency improvement. No samples or slower trials were discarded.

## Allocation and ARC-call replay

Plain 100,000-row, three-pane, depth-8 fixture; 12 scroll events plus two activations
per cycle, `--samples 3 --warmup 1`. The allocation probe is enabled only in this
separate replay, never in the timing matrix. Totals include startup, JSON reporting
and the benchmark's metrics replay, through the probe-report destructor; later
teardown is outside that snapshot.

| Intercepted work | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| malloc calls | 13,227,686 | 12,117,319 | −8.4% |
| calloc calls | 38 | 38 | unchanged |
| realloc calls | 0 | 0 | unchanged |
| Requested allocation bytes | 3,904,954,564 | 1,651,605,247 | −57.7% |
| swift_retain calls | 37,483,509 | 35,681,018 | −4.8% |
| swift_release calls | 55,652,614 | 53,599,838 | −3.7% |

Requested bytes measure cumulative traffic, not RSS or peak retained memory.
Intercepted ARC calls include null/immortal references and exclude runtime-internal
calls and retain_n/release_n; they are not a count of all reference-count updates.

## User-CPU samples

Separate matched plain depth-8 runs, `--samples 30 --warmup 3`, using the diagnostic
virtual-timer sampler with the preserved executables. Baseline captured 7,334
samples; candidate 5,322. Both report zero capacity overflow, and each TSV line count matches its reported
sample count. Signal coalescing and
kernel timer resolution are not measured; sample counts are not absolute CPU times.
Capture includes startup and four instrumented cycles alongside 33 uninstrumented
cycles, rather than claiming an input-only or completely uninstrumented profile.
The virtual timer charges all process threads but sends a process-directed signal;
samples describe the eligible receiving thread, not an unbiased per-thread CPU
profile. The fixture's traversal is synchronous MainActor work, with possible
runtime helper threads. See the [probe limitations](README.md#cpu-sampling-boundary).

| Self/instruction location | Baseline samples / share | Candidate samples / share |
| --- | ---: | ---: |
| Segment initializeWithCopy witness | 336 / 4.58% | 41 / 0.77% |
| Segment destroy witness | 277 / 3.78% | 15 / 0.28% |
| swift_release | 950 / 12.95% | 640 / 12.03% |
| swift_retain | 653 / 8.90% | 574 / 10.79% |

The copy/destruction hotspot shrank materially. ARC still matters: retain's share
of the smaller total increased even though intercepted retain calls decreased.
These samples support the copying diagnosis, not attribution of all frame or
registration cost to paths.

## Deterministic work and correctness

All paired replay work counters and drawing-command counts match. The input burst
still paints nothing and emits zero drawing commands; idle polling does no work,
callbacks remain fresh, presentation does not replay actions, and teardown reports
zero live resolved nodes and observation subscriptions.

Remaining preparation work is substantial and deliberately not hidden:

| Interactive depth | Body evaluations / burst | Measurement requests / burst | Registration visits / burst | Peak resolved nodes |
| --- | ---: | ---: | ---: | ---: |
| 0 | 370 | 6,556 | 5,522 | 403 |
| 8 | 370 | 128,308 | 19,762 | 6,721 |
| 16 | 370 | 387,476 | 34,002 | 21,593 |

Those counts do not change with this patch. The existing simple nested-control
linear-growth test is not a claim that this compound fixture has linear allocation
cost. Current-phase children can need their own idle measurement descendants,
with different focus contexts. Sharing those trees without a validity contract is
outside this change; the path optimization does not establish such a contract.

Validation on the final implementation:

- Full root suite: 556 tests passed, including structural identity, stack evaluation,
  raw-keyboard freshness, registration refresh, operation-local layout, runtime,
  observation, paint isolation, and native backend tests.
- Benchmark suite: 7 tests passed, including both plain and identified freshness
  replays and comparison compatibility checks.
- New deterministic tests cover batch splits across the representation boundary,
  forced collisions before/at/after it, typed keys and every segment kind, shared
  ancestor storage, non-rehashing of ancestors, sibling independence, predicate
  traversal and storage release when owners disappear.
- Both diagnostic C tools compile with `-Wall -Wextra -Werror`; release benchmark
  binaries build successfully. No timing thresholds were added to correctness tests.

## Reproduction

Apply the three benchmark source changes (`StressScene.swift`, `StressOptions.swift`,
`StressBenchmark/main.swift`) to a clean baseline worktree so both builds use the
same fixture and reporting code. Build each in its own scratch directory:

```sh
swift build --package-path Benchmarks --scratch-path /tmp/chroma-benchmark-build \
  -c release -Xswiftc -g -j 2 --product StressBenchmark
```

Keep the built executable with its font resources. For both executables, run
three serial trials of each combination, alternating baseline/candidate order:

```sh
for depth in 0 8 16; do
  for identified in 0 1; do
    "$BENCHMARK" --rows 100000 --panes 3 --events 12 \
      --depth "$depth" --identified "$identified" --samples 10 --warmup 3
  done
done
```

Preserve the JSON reports and compare configuration, commands and all work counters
before interpreting timings. See [README](README.md) for separate probe commands
and their measurement boundaries. Physical-display and ShapeTree validation remain
#111 work.
