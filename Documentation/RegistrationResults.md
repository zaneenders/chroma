# Registration separation: Linux validation, 2026-10-02

The migrated pre-input path performs **zero painting** in the virtualized control fixture, while preserving fresh callbacks between coalesced events. These measurements do **not** demonstrate a wall-clock speedup. Full collection identity scans still dominate the 10,000-row fixture, and the separately built historical nested-layout benchmarks show modest regressions.

See [pipeline and migration contract](RegistrationPipeline.md), [benchmark instructions](../Benchmarks/README.md#paint-free-registration), and the [complete aggregate JSON](../Benchmarks/reports/registration-linux-2026-10-02.json).

## Environment and method

- Debian 13.6 x86_64, Swift 6.4 release, virtualized AMD EPYC 9V74 allocation with 9 visible logical processors and approximately 10 GiB RAM. Native checks used matching Wayland 1.26.0 headers and libraries.
- Historical baseline: main `e46e475ded8be5d4df569d534b94a32102e48d23`. The pristine archive used for baseline execution was `ce73c99ae055b6ba1ba75cfcd91f338d91fd539d`; `Sources`, `Tests`, `Benchmarks`, and `Package.swift` are identical between those revisions.
- Baseline and candidate used the same release configuration, datasets, viewport, input sequence, warmup, and sampling method. Compilation finished before timing; no competing builds or tests ran during either window. The JSON records binary SHA-256 hashes and UTC windows.
- Existing nested-layout benchmarks: 20 session-style rows, 400×300 viewport, depths 1/3/5, 3 warmup frames, then 20 timed frames per case, repeated in 5 trials. Tables show the median of trial p50s and the median of trial p95s, not a pooled percentile.
- Existing input benchmark: 200×200 viewport, 1,000/100,000/1,000,000 rows, identified/unkeyed and deferred/replaced roots. Five trials yield 5 cold and 25 warm samples per case; their percentiles are pooled. Full results are in the JSON.

## Historical before/after

Times are milliseconds. The selected scroll workloads preserve their row-body and output-command counts.

| Workload | Baseline p50 / p95 | Candidate p50 / p95 | p50 change | Row bodies / output commands |
|---|---:|---:|---:|---:|
| Ordinary layout, depth 1, scroll | 1.228 / 1.355 | 1.247 / 1.395 | +1.5% | 40 / 65 |
| Ordinary layout, depth 5, scroll | 1.487 / 1.689 | 1.550 / 1.821 | +4.3% | 40 / 64 |
| Interactive layout, depth 1, scroll | 1.845 / 2.140 | 1.902 / 2.076 | +3.1% | 80 / 64 |
| Interactive layout, depth 5, scroll | 6.451 / 6.862 | 6.574 / 7.024 | +1.9% | 240 / 64 |
| 1,000 identified rows, deferred root, warm | 0.269 / 0.300 | 0.282 / 0.340 | +4.8% | — / 16 |
| 1,000,000 identified rows, deferred root, warm | 127.426 / 131.365 | 126.061 / 130.503 | −1.1% | — / 16 |

The ordinary depth-5 scroll trial-p50 ranges were 1.471–1.509 ms before and 1.514–1.604 ms after. The interactive depth-5 scroll ranges were 6.249–7.004 ms before and 6.434–6.894 ms after. These are modest measured regressions, with overlapping ranges in the interactive case. This single-host, sequential comparison does not isolate every source of overhead or establish statistical significance. It must not be presented as an application speedup.

## Same-binary mechanism comparison

`RegistrationBenchmark` uses an identical deferred root containing a fixed increment button and 10,000 identified virtualized rows (30 points high, 1-point spacing) in a 480×360 viewport. The legacy mode adds one identity-preserving custom primitive whose default registration adapter paints the underlying tree. Its small wrapper overhead is included; this is a mechanism baseline, not another historical executable.

Each of 5 trials contains 40 samples per mode, alternating mode order. Every sample starts a fresh host, measures its initial frame, warms up for 5 activation-pair/scroll/presentation cycles, then measures two activations, one scroll event, one coalesced presentation, and 1,000 idle scheduling polls. Timing runs with metrics disabled; a separate identical replay collects counters. Initial-frame timing excludes fixture allocation and is not process-cold startup.

| Phase | Legacy p50 / p95 (ms) | Paint-free p50 / p95 (ms) | Legacy → paint-free paints | Legacy → paint-free emitted commands |
|---|---:|---:|---:|---:|
| Initial frame | 5.458 / 6.097 | 5.380 / 6.694 | 52 → 25 | 80 → 41 |
| Two activations, no presentation | 1.438 / 1.688 | 1.433 / 1.673 | 52 → 0 | 81 → 0 |
| Scroll input, no presentation | 0.711 / 0.847 | 0.708 / 0.849 | 26 → 0 | 40 → 0 |
| Active presentation | 0.729 / 0.922 | 0.726 / 0.829 | 26 → 25 | 43 → 43 |
| 1,000 idle scheduling polls | 0.035 / 0.035 | 0.035 / 0.035 | 0 → 0 | 0 → 0 |

For the activation pair, the legacy/native trial-p50 ranges were 1.424–1.482 / 1.411–1.458 ms. For scroll input they were 0.706–0.732 / 0.703–0.721 ms. Those overlapping ranges do not support a meaningful latency improvement.

Counters are deterministic across all 5 trials:

- Both modes evaluate 2 bodies, make 6 measurement requests, and construct 22 visible row controls per activation pair. One scroll event halves those counts. Identified row metadata still scans the entire collection on each deferred-root evaluation.
- Dedicated registration visits for an activation pair are 2 in the compatibility mode and 50 in the migrated mode. Compatibility installs behavior during the 52 counted paint visits; registration visits are not a count of individual installed handlers.
- The migrated path has zero compatibility fallbacks in every phase. The baseline reports the exact caller, `RegistrationFixtures.LegacyRegistrationRoot`, twice per activation pair and once per scroll or initial registration.
- The migrated/legacy peak resolved-node counts are 5/6, and live resolved nodes return to zero at every phase boundary. These nodes and proposal caches are traversal-scoped, not a persistent retained tree.
- Each live fixture has one frame observation subscription object; closing it releases that object. Both lifetime gauges are asserted to be zero after every close.
- Initial output has 41 commands and active output has 43 in both modes. The extra legacy commands above are produced during registration and discarded.
- Idle produces zero frames and zero pipeline work. This is a synchronous scheduler assertion, not a native idle-CPU or asynchronous event-loop measurement.

Every activation closure captures the prior counter value during reconciliation. Two events without presentation must increment it by two; every replay asserts this, and presentation must not replay either action.

## Validation and limits

- Native root suite: **433 tests passed**, comprising 421 Chroma tests and 12 WaylandBackend tests. This includes the actual Linux backend and app targets.
- Benchmark package: **7 tests passed**, including virtualized paint-free/legacy comparison, identical initial output, current coalesced callbacks, initial-frame event ordering, and idle behavior.
- ShapeTree desktop: **161 tests passed**, and the native `ShapeTreeDesktop` release build with `-Xswiftc -g` passed, with an unpublished companion migration patch. No private application source is included in this repository.
- New headless scheduling tests explicitly drain controlled observation delivery, verify observed changes and focus requests schedule frames, and verify return to idle. Benchmark idle polls alone would not establish those asynchronous semantics.
- Live GUI smoothness, macOS/Metal behavior, GPU time, native event latency, and native idle CPU were **not validated**. No display server was available for an interactive ShapeTree run. Native backend unit tests do not substitute for that validation.

## Reproduce

Install a Swift 6.4 toolchain and the repository's native Linux dependencies (including compatible Wayland headers/libraries), or run on a supported macOS environment. From the repository root:

```sh
swift test
swift test --package-path Benchmarks
swift build --package-path Benchmarks -c release
bin_dir=$(swift build --package-path Benchmarks -c release --show-bin-path)
for trial in 1 2 3 4 5; do
  "$bin_dir/RegistrationBenchmark" --rows 10000 --samples 40 --warmup 5 --idle-polls 1000 \
    > "registration-$trial.json"
  "$bin_dir/LayoutBenchmark" > "layout-$trial.json"
  "$bin_dir/LayoutBenchmark" --interactive > "interactive-$trial.json"
  "$bin_dir/InputFrameBenchmark" > "input-$trial.txt"
done
```

For a historical comparison, repeat the existing layout/input commands against a pristine baseline release build using the same machine and toolchain. The old benchmark package requires its checkout directory to be named `chroma`; the candidate manifest explicitly names the local dependency and removes that directory-name dependency. Build both revisions before starting measurements and keep other builds, tests, and profiling idle. Preserve executable hashes and the raw reports; do not compare these Linux numbers directly with earlier macOS handoff measurements.
