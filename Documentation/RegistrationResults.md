# Architecture validation: Linux, 2026-10-02

The final implementation provides fresh, ordered input through paint-free registration, operation-owned painting snapshots, and explicit bounded geometry reuse. The cache removes repeated measurement/placement computations in the opted-in fixture while preserving fresh bodies and callbacks. **These results do not establish an overall latency improvement.** Historical nested-layout medians regress, and the application input tail is worse.

See the [pipeline and migration contract](RegistrationPipeline.md), [handoff checklist](ArchitectureHandoffChecklist.md), and [benchmark instructions](../Benchmarks/README.md#paint-free-registration). Raw reports, binary hashes, source hashes, aggregation scripts and validation logs are supplied in the separate core evidence archive; application evidence and its migration patch are a separate companion archive. Earlier milestone and pre-optimization measurements are not the final results below.

## Method and provenance

- Debian 13.6 x86_64, Swift 6.4 release, virtualized AMD EPYC 9V74 allocation, 9 visible logical processors and approximately 10 GiB RAM; matching Wayland 1.26 headers/libraries.
- Historical baseline: pristine `ce73c99ae055b6ba1ba75cfcd91f338d91fd539d`, with implementation equivalent to published `6242fe8` / merged main `e46e475`. Candidate measurements use the final source freeze, including the bounded plain-text/background/snapshot optimizations.
- Both revisions use identical release configurations, datasets, viewports, input sequences, warmup and sampling. Binaries were built before measurement; no competing compiler, tests, or profiler ran during timing. Timings disable pipeline instrumentation; separate matching captures collect work counters.
- Original layout fixtures: 20 rows, 400×300 viewport, depths 1/3/5, 3 warmup frames, 20 timed frames per case, 5 trials. Reported values are the median of trial p50s/p95s. A rendered no-input frame is not an idle-CPU measurement.
- Original input fixture: 200×200 viewport, 1k/100k/1m identified or unkeyed rows, deferred/replaced roots. Five trials pool 5 cold or 25 warm samples per workload.

## Historical before/after

Milliseconds; selected depth-5 row-body and drawing-command counts are unchanged.

| Workload | Baseline p50 / p95 | Final p50 / p95 | p50 change | Bodies / output commands |
|---|---:|---:|---:|---:|
| Ordinary depth 5, no input | 0.772 / 1.025 | 0.844 / 0.943 | +9.3% | 20 / 64 |
| Ordinary depth 5, scroll | 1.497 / 1.747 | 1.623 / 1.745 | +8.4% | 40 / 64 |
| Interactive depth 5, no input | 3.233 / 3.832 | 3.488 / 3.808 | +7.9% | 120 / 64 |
| Interactive depth 5, scroll | 6.338 / 6.919 | 6.815 / 7.574 | +7.5% | 240 / 64 |
| 1m unkeyed, deferred root, warm | 0.101 / 0.147 | 0.149 / 0.179 | +47.2% | — / 16 |
| 1m identified, deferred root, warm | 126.137 / 133.394 | 126.106 / 135.101 | −0.02% | — / 16 |

The unkeyed increase is approximately 0.048 ms in absolute terms. Ordinary depth-5 scroll trial-p50 ranges were 1.477–1.561 ms before and 1.617–1.629 ms after; interactive scroll ranges were 6.181–7.288 and 6.698–7.873 ms. This sequential, single-host comparison does not establish statistical significance or an application speedup. Full collection identity scans remain a separate cost.

A bounded overhead investigation removed repeated opaque-wrapper child construction, reused prepared background nodes directly, and avoided snapshot allocations for plain nonwrapping/nonselectable text. The final figures include those changes. The remaining cost buys explicit phase isolation and correctness; this proposal does not justify enabling retained geometry everywhere or claiming a general performance improvement.

## Three-mode registration fixture

One binary renders the same deferred root: a fixed increment button and 10,000 identified virtualized rows, 30-point height plus 1-point spacing, in a 480×360 viewport. The legacy variant adds an identity-preserving draw-to-register adapter; the cached variant wraps the fresh root in `CachedLayout`. These are same-binary mechanism comparisons, not additional historical executables.

Five trials contain 40 samples per mode with alternating mode order, 5 warmup activation-pair/scroll/presentation cycles, and separate counter replays. Initial timing excludes fixture allocation. Values below are median trial p50/p95, milliseconds.

| Phase | Legacy adapter | Paint-free | Paint-free + cache |
|---|---:|---:|---:|
| Initial frame | 5.485 / 6.288 | 5.484 / 6.793 | 5.628 / 6.318 |
| Two activations before presentation | 1.456 / 1.713 | 1.485 / 1.650 | 1.518 / 1.815 |
| Scroll before presentation | 0.720 / 0.797 | 0.726 / 0.870 | 0.739 / 0.920 |
| Coalesced presentation | 0.745 / 0.863 | 0.759 / 0.948 | 0.765 / 0.920 |
| Explicit invalidation then input | 0.739 / 0.890 | 0.738 / 0.866 | 0.797 / 0.955 |
| 1,000 idle scheduler polls | 0.034 / 0.039 | 0.035 / 0.053 | 0.035 / 0.036 |

Work counts are identical across all five trials. “Computations” below means resolved measurement requests minus cache hits, not only primitive calls.

| Phase | Measurement computations: uncached → cached | Cached placement hits | Bodies / rows built, both modes |
|---|---:|---:|---:|
| Initial frame | 6 → 3 | 1 | 2 / 22 |
| Two activations | 6 → 0 | 2 | 2 / 22 |
| Scroll input | 3 → 0 | 1 | 1 / 11 |
| Presentation | 3 → 0 | 1 | 1 / 11 |
| Explicit invalidation then input | 3 → 3 | 0 | 1 / 11 |

- Registration painting is eliminated: activation-pair paint visits/commands fall from 52/81 to 0/0; scroll falls from 26/40 to 0/0. Both migrated modes have zero compatibility fallbacks. Only `LegacyRegistrationRoot` deliberately uses the adapter.
- Placement-cache hits avoid requesting sizes at all, so steady cached phases have zero retained **measurement** hits as well as zero measurement computations. Fresh bodies, row construction and identity scanning remain.
- Both migrated modes emit 41 commands initially and 43 in active presentation. Two captured-count actions before presentation must increment by two; every replay checks this and checks that presentation does not replay actions.
- Cached mode keeps 3 geometry nodes and 6 subscription objects; uncached/legacy modes keep 0 geometry nodes and 1 frame subscription. Resolved nodes return to zero at phase boundaries. Every close asserts zero retained nodes, resolved nodes and subscriptions.
- Explicit invalidation is followed immediately by input without queued observation delivery. Idle produces zero frames and zero pipeline work; this synchronous check does not measure native idle CPU. Separate controlled-observation tests cover asynchronous return to idle.

## Real ShapeTree application graph

The companion follows ShapeTree `4e5432d99687af4714169ee419d344d680d61fc0` and Scribe `589b312a952db70b0a06a303bbf035f7e9a86501`, preserving their NativeApp integration. Its freshly built release test process exercises actual application blocks with 1,000 sessions, 40 transcript messages and an 1180×820 viewport. Each of 5 trials per variant warms up for 5 cycles, then measures 20 cycles of four ±60-point sidebar scroll events followed by presentation. The legacy wrapper preserves identity. Both variants include the small sidebar cache adoption.

These application percentiles are **pooled** across 100 measured cycles per variant (first frame: 5 fresh hosts); p95 uses linear interpolation. They are not the synthetic fixture's median-of-trial aggregation.

| Phase | Legacy p50 / p95 (ms) | Explicit phases p50 / p95 (ms) |
|---|---:|---:|
| Fresh-host first frame | 47.881 / 51.928 | 46.810 / 57.640 |
| Four scroll events before presentation | 90.054 / 100.638 | 89.083 / 120.619 |
| Coalesced presentation | 22.870 / 27.778 | 22.830 / 27.049 |

Application medians are near-flat; the input-batch p95 increases from **100.638 to 120.619 ms**. No overall latency improvement is claimed.

Per four-event batch, paint visits fall **2,793 → 0**, emitted commands **1,327 → 0**, compatibility fallbacks **4 → 0**, and text-layout constructions **329 → 20**. Bodies remain **643**, measurement requests **6,011** with **377** hits, retained nodes **6**, and subscriptions **28**. The large graph-reconciliation/measurement cost remains visible. Both variants produce zero idle frames, offsets 0/240, and 332 initial output commands. Private application source is supplied only in the companion patch.

## Validation and limits

- **463 Chroma + 13 Wayland tests**, **7 benchmark-package tests**, and **172 optimized ShapeTree release tests** pass. The native application release executable and benchmark products build successfully; the application executable includes debug symbols.
- Changed Swift files pass strict formatting. Whole-tree lint still reports seven unchanged baseline warnings. Two identity-diagnostic stderr assertions fail only in optimized core release tests and reproduce on the unmodified published baseline; those tests were not weakened.
- Independent final review closed the raw-key freshness and selectable-text ordering findings and reviewed the final bounded fast paths. Source hashes and logs accompany the evidence.
- Native interactive smoothness, native event latency/idle CPU, GPU timing and macOS/Metal execution remain **unverified**. The Linux compositor's socket creation is blocked by `EPERM`; the permitted CPU-profiler attempt collected zero samples. Headless graph measurements are not a native GUI profile.

## Reproduce

Use Swift 6.4 with the repository's native dependencies. Build and test before timing; keep other builds, tests and profilers idle.

```sh
swift test
swift test --package-path Benchmarks
swift build --package-path Benchmarks -c release
bin_dir=$(swift build --package-path Benchmarks -c release --show-bin-path)
for trial in 1 2 3 4 5; do
  "$bin_dir/RegistrationBenchmark" --rows 10000 --samples 40 --warmup 5 --idle-polls 1000 > "registration-$trial.json"
  "$bin_dir/LayoutBenchmark" > "layout-$trial.json"
  "$bin_dir/LayoutBenchmark" --interactive > "interactive-$trial.json"
  "$bin_dir/InputFrameBenchmark" > "input-$trial.txt"
done
```

Repeat the original layout/input workloads against a pristine historical release build with identical settings. Its checkout directory must be named `chroma`; the current benchmark manifest supports other names. Preserve binary hashes and raw reports. The supplied core archive includes the runners and aggregation scripts; the companion includes the application fixture, exact dependency receipt and reproduction instructions. Do not compare these Linux timings directly with historical macOS profiles.
