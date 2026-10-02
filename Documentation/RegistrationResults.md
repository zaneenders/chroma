# Simplified registration / painting results

The revised implementation keeps fresh ordered input and paint-free registration,
removes the unearned `CachedLayout` / `LayoutCache` experiment, and replaces the
hidden cross-call child-order protocol with an operation-local prepared-child API.
Production source is **92 lines added / 443 removed, net −351 lines**, relative to
published PR revision `a3ca873`. This is an architectural simplification with
verified phase isolation. **The core benchmarks do not establish an overall
latency improvement.** The separately revised headless application fixture improves
substantially after combined preparation and sidebar-metadata changes; that result
does not isolate a core-library speedup.

See the [pipeline contract](RegistrationPipeline.md),
[handoff checklist](ArchitectureHandoffChecklist.md), and
[benchmark instructions](../Benchmarks/README.md#paint-free-registration).
The new evidence archive preserves the old published results document and binary
hashes separately. Its fresh three-revision measurements supersede the former
three-mode table as evidence for this revision; cached-mode output is historical
only. The existing variable-row and text caches remain, and resolved-node proposal
memoization still expires with its operation. There is no new cross-update geometry
validity or reuse contract.

## Method and provenance

- Debian 13.6 x86_64, Swift 6.4 release, virtualized AMD EPYC 9V74 allocation,
  9 visible logical processors, approximately 10 GiB RAM, and matching Wayland
  1.26 headers/libraries.
- Original baseline: the pristine `ce73c99ae055b6ba1ba75cfcd91f338d91fd539d`
  export, whose implementation matches published `6242fe8` / merged main
  `e46e475`. Published PR: preserved executables corresponding to `a3ca873`.
  Simplified: final reviewed source freeze, with 131 production-file hashes and
  an additional test/benchmark/input manifest in the evidence archive.
- All executable hashes were recorded. Previously published binaries and reports
  were not overwritten. All three revisions were measured afresh in one quiet
  collection window, with matching release toolchain, dependencies and workloads.
  Revision order alternated by trial; no compiler, test or profiler ran during
  collection.
- Original layout fixtures: 20 rows, 400×300 viewport, depths 1/3/5, 3 warmup
  frames, 20 measured frames per case, 5 trials. Tables report the median of trial
  p50s/p95s. A rendered no-input frame is not an idle-CPU measurement.
- Original input fixture: 200×200 viewport, 1k/100k/1m identified or unkeyed rows,
  deferred/replaced roots. Five trials pool 5 cold or 25 warm samples per workload;
  input p95 uses the nearest-rank sample.
- Registration timings disable `PipelineMetrics`; separate matching replays
  collect counters. Source changes to this fixture remove only the third mode,
  cache-only phase and fields, alongside stronger equivalence/idle tests.

## Fresh original / published / simplified comparison

Milliseconds, p50 / p95. The last columns compare p50, not p95. These are selected
workloads; all depths, list sizes and cold/warm cases are in the raw evidence.

| Workload | Original baseline | Published `a3ca873` | Simplified | vs published | vs original |
|---|---:|---:|---:|---:|---:|
| Ordinary depth 5, no input | 0.776 / 0.912 | 0.874 / 1.105 | 0.845 / 1.012 | −3.4% | +8.9% |
| Ordinary depth 5, scroll | 1.506 / 1.818 | 1.676 / 2.013 | 1.675 / 1.985 | ≈0.0% | +11.3% |
| Interactive depth 5, no input | 3.388 / 3.822 | 3.640 / 4.222 | 3.501 / 4.050 | −3.8% | +3.3% |
| Interactive depth 5, scroll | 6.461 / 6.855 | 7.149 / 7.788 | 6.876 / 7.340 | −3.8% | +6.4% |
| 1m unkeyed, deferred root, warm | 0.102 / 0.136 | 0.154 / 0.196 | 0.144 / 0.337 | −6.5% | +40.8% |
| 1m identified, deferred root, warm | 127.792 / 139.587 | 128.954 / 152.758 | 131.516 / 139.516 | +2.0% | +2.9% |

All three revisions have the same selected depth-5 body counts: 20/40 for ordinary
no-input/scroll, 120/240 for interactive no-input/scroll, and 64 output commands.
Both selected million-row input workloads produce 16 commands. Full collection
identity scans remain a separate cost.

The simplified ordinary-scroll trial-p50 range is 1.610–1.781 ms, against
1.630–1.736 ms for the published PR and 1.487–1.567 ms for the original baseline.
Interactive-scroll ranges are 6.689–7.077, 6.852–7.735 and 6.237–7.273 ms,
respectively. These single-host measurements do not establish statistical
significance. The unkeyed absolute p50 difference from the original is about
0.042 ms, while its p95 is worse in this run. The lower selected nested-layout
medians relative to the published PR do not justify a general performance claim.

## Two-mode registration fixture

One binary renders a fixed increment button and 10,000 identified virtualized rows
through the same deferred root, with 30-point rows, 1-point spacing and a 480×360
viewport. The legacy variant adds an identity-preserving draw-to-register adapter.
It is a same-binary mechanism baseline, distinct from the historical executable
comparison above.

Five trials have 40 samples per mode, alternating mode order, 5 warmup
activation-pair/scroll/presentation cycles, and separate counter replays. Initial
frame timing excludes fixture allocation. The published binary still runs its
third cached mode and extra invalidation phase; its raw reports are preserved.
The shared initial, activation, scroll and presentation workloads precede that
removed phase and are unchanged. Idle polling now follows active presentation
directly, whereas the old binary first drained an invalidation event. Overall
process durations across these different mode/phase sets are not comparable.

Median trial p50 / p95, milliseconds:

| Phase | Published legacy | Published paint-free | Simplified legacy | Simplified paint-free |
|---|---:|---:|---:|---:|
| Initial frame | 5.703 / 6.867 | 5.730 / 6.475 | 5.800 / 7.955 | 5.806 / 7.684 |
| Two activations before presentation | 1.474 / 1.700 | 1.468 / 1.765 | 1.525 / 1.893 | 1.504 / 2.054 |
| Scroll before presentation | 0.724 / 0.922 | 0.726 / 0.881 | 0.728 / 0.889 | 0.739 / 1.003 |
| Coalesced presentation | 0.745 / 0.978 | 0.769 / 0.892 | 0.754 / 1.023 | 0.763 / 1.018 |
| 1,000 idle scheduler polls | 0.035 / 0.036 | 0.035 / 0.040 | 0.035 / 0.054 | 0.035 / 0.062 |

The shared work counters are **identical before and after simplification** and
across all five trials. The former cached mode is not folded into that statement.

| Phase | Bodies / rows built | Measurement requests / cache hits | Legacy paint visits / commands | Paint-free paint visits / commands |
|---|---:|---:|---:|---:|
| Initial frame | 2 / 22 | 6 / 0 | 53 / 80 | 25 / 41 |
| Two activations | 2 / 22 | 6 / 0 | 52 / 81 | 0 / 0 |
| Scroll input | 1 / 11 | 3 / 0 | 26 / 40 | 0 / 0 |
| Presentation | 1 / 11 | 3 / 0 | 27 / 43 | 25 / 43 |
| Idle polls | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

- Both modes emit 41 initial and 43 active output commands. The extra legacy
  commands during registration are discarded. Only `LegacyRegistrationRoot`
  uses the compatibility adapter; paint-free fallbacks are zero.
- Two captured-count callbacks before presentation must increment by two. Every
  replay checks freshness and ensures presentation does not replay either action.
  Tests additionally compare complete initial and post-input frames between modes.
- Resolved nodes return to zero at phase boundaries; one frame observation
  subscription remains while the fixture is open. Every close asserts zero live
  resolved nodes and subscriptions. The removed retained-geometry metrics are no
  longer part of the new schema.
- Idle produces zero frames and pipeline work. Tests also verify no row
  construction or counter changes across 1,000 polls. These synchronous checks do
  not measure native idle CPU; separate observation-delivery tests cover async idle.

The paint-free activation-pair p95 rises from 1.765 to 2.054 ms in this run. Phase
isolation remains a correctness result, not evidence of a synthetic latency win.

## Real ShapeTree application graph

The revised companion follows ShapeTree `4e5432d99687af4714169ee419d344d680d61fc0`
and Scribe `589b312a952db70b0a06a303bbf035f7e9a86501`. Against the old companion
migration on that same baseline, production Swift changes are **135 added / 234
removed, net −99 lines** across seven files. It removes sidebar cache adoption,
uses the public operation-local preparation contract, and derives running state
from each existing row value instead of repeating a full-session search per item.

The preserved published release runner and revised release runner were both
measured afresh after the core timing window. Their synthetic fixture exercises
actual application blocks: 1,000 sessions, 40 transcript messages, 1180×820 viewport,
5 trials per variant, 5 warmups and 20 measured cycles per trial. Each cycle applies
four ±60-point sidebar scroll events, then one presentation. Metrics are disabled
for timings and collected separately. Application percentiles pool 100 steady-state
samples per variant and use linear interpolation; first-frame estimates have only
5 fresh-host samples. These are not the core tables' median-of-trial percentiles.

Explicit update/paint path, p50 / p95 milliseconds:

| Phase | Published companion | Revised companion | p50 change |
|---|---:|---:|---:|
| Fresh-host first frame | 47.554 / 50.810 | 13.615 / 14.018 | −71.4% |
| Four scroll events before presentation | 90.343 / 100.947 | 23.858 / 29.410 | −73.6% |
| Coalesced presentation | 23.079 / 27.207 | 6.243 / 7.116 | −73.0% |

This is a substantial improvement for the revised **headless application fixture**.
It measures the combined preparation and sidebar-metadata changes, including
removal of the quadratic lookup. No ablation isolates their individual effects;
these ratios must not be attributed to core cache removal or phase separation
alone. The revised legacy-adapter input batch is also faster, at 24.122 / 26.315 ms;
the explicit path has a similar median and a worse p95 than that same-binary
mechanism baseline. No native GUI smoothness or general Chroma speedup is claimed.

Exact work per four-event registration batch on the explicit path:

| Counter | Published companion | Revised companion |
|---|---:|---:|
| Body evaluations | 643 | 643 |
| Measurement requests / cache hits | 6,011 / 377 | 6,035 / 385 |
| Placement / registration visits | 2,789 / 2,789 | 2,769 / 2,769 |
| Live observation subscriptions | 28 | 21 |
| Text-layout constructions | 20 | 20 |
| Paint visits / commands / compatibility fallbacks | 0 / 0 / 0 | 0 / 0 / 0 |
| Live resolved nodes at boundary | 0 | 0 |

Graph construction and measurement remain visible work rather than being skipped
by retained geometry. Both revisions and both modes produce 332 initial commands,
reach offsets 0/240 and produce zero idle frames. The new companion archive contains
its exact source/dependency receipts, raw timing and work reports, patch and clean
apply checks. The old dynamically loaded test library was preserved and verified
to contain its original statically linked application/Chroma code; it did not load
the revised source during the historical replay.


## Validation and limits

- **470 Chroma + 13 Wayland debug tests** and **8 benchmark-package debug tests**
  pass against the final source. Final release benchmark products build.
- The companion passes **173 application tests / 34 suites in both debug and
  release**, and its native application release executable builds.
- Strict formatting passes for changed Swift files, and `git diff --check` passes.
  The prior whole-tree lint warnings and release-only identity-diagnostic stderr
  assertions are historical baseline evidence. A fresh optimized core aggregate
  suite was not run for this revision; it is not represented as a pass.
- Independent review exercises prepared-child rebuilding, conditional structure,
  inherited focus/command identity, nested wrappers and direct-draw compatibility.
  The valid-frame regression demonstrated the pre-fix direct-draw failure, and all
  affected container cases pass in the final source. Review and source-hash
  receipts accompany the evidence.
- Native interactive smoothness, event latency/idle CPU, GPU timing and macOS/Metal
  execution remain **unverified**. Previous Linux compositor socket creation was
  blocked by `EPERM`, and the permitted CPU-profiler attempt collected zero samples.
  Headless graph measurements do not substitute for a native GUI profile.

## Reproduce

Use Swift 6.4 and matching native dependencies. Build and test before timing, then
keep other compilers, tests and profilers idle.

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

For historical comparisons, preserve independently built original and published
binaries, then run the shared workloads sequentially with alternating revision
order. The new evidence archive includes `run-simplification-comparison.py`, the
aggregation script, raw outputs, binary/source hashes, previous published results,
and validation/review logs. The original checkout directory must be named `chroma`;
the current benchmark manifest supports other names. The separate companion
archive contains the private application patch, fixture, dependency receipt and
reproduction instructions. Do not compare these Linux timings directly with
historical macOS profiles.
