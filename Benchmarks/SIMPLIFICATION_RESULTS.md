# Simplification CPU comparison

Final selection: retain review points 2–6; defer the interaction-handle rewrite (point 1). The selected production snapshot is the no-handles ablation below. Earlier adverse measurements remain in the evidence.

Baseline: `1ce09ac1acb34af807191692ddd2601d049fca4d`. Candidate: the production source fingerprint below, included with this report.

Swift 6.4 release builds on a shared Intel Xeon Platinum 8573C Linux container, with `CHROMA_HEADLESS_ONLY=1`. Three adjacent process trials per workload, alternating baseline/candidate, candidate/baseline, baseline/candidate. Both variants use CPU3 affinity and `SWIFT_DETERMINISTIC_HASHING=1`; type-identity addresses can still vary. Every process ran serially after all builds/tests stopped. Timing instrumentation was disabled; work counters use separate replays.

- Baseline source SHA-256: `25f10199efb0e95167676096cb8a206fc7c5dd0fe87beb65ff7aace721f870a6`
- Candidate source SHA-256: `08c32f4555635eb34bdd6e22df9df85a862f858a42f6a722753ba3279e1737e2`
- Fingerprint scope: sorted SHA-256/path inventory for all files under Sources and Benchmarks/Sources.
- Raw trials, binary hashes, configuration, sample counts and counters: [JSON](SIMPLIFICATION_RESULTS.json).

The table shows the median of each trial’s p50/p95 milliseconds. Negative changes are faster. Shared-host variance prevents universal performance claims. All recorded drawing-command counts and row-emission counts match.

| Workload | Case | p50 baseline → candidate | Change | p95 baseline → candidate | Change |
|---|---|---:|---:|---:|---:|
| layout | depth 1, none | 0.570 → 0.573 | +0.5% | 0.816 → 0.966 | +18.4% |
| layout | depth 1, scroll | 1.031 → 1.055 | +2.3% | 1.917 → 1.845 | -3.8% |
| layout | depth 3, none | 0.656 → 0.635 | -3.2% | 1.092 → 0.874 | -20.0% |
| layout | depth 3, scroll | 1.111 → 1.080 | -2.7% | 1.476 → 1.376 | -6.7% |
| layout | depth 5, none | 0.642 → 0.659 | +2.6% | 0.840 → 0.972 | +15.6% |
| layout | depth 5, scroll | 1.204 → 1.215 | +0.9% | 1.635 → 1.588 | -2.9% |
| interactive-layout | depth 1, none | 0.597 → 0.577 | -3.3% | 0.785 → 0.867 | +10.5% |
| interactive-layout | depth 1, scroll | 1.049 → 1.000 | -4.7% | 1.289 → 1.649 | +27.9% |
| interactive-layout | depth 3, none | 0.666 → 0.627 | -5.8% | 1.249 → 0.937 | -25.0% |
| interactive-layout | depth 3, scroll | 1.205 → 1.182 | -1.9% | 2.113 → 1.553 | -26.5% |
| interactive-layout | depth 5, none | 0.747 → 0.690 | -7.6% | 1.087 → 1.036 | -4.7% |
| interactive-layout | depth 5, scroll | 1.398 → 1.674 | +19.7% | 1.938 → 3.118 | +60.9% |
| markdown | static | 6.087 → 6.311 | +3.7% | 8.819 → 10.063 | +14.1% |
| markdown | streaming | 24.453 → 26.103 | +6.7% | 31.738 → 68.397 | +115.5% |
| markdown | narrow | 6.824 → 12.909 | +89.2% | 19.385 → 31.509 | +62.5% |
| markdown | long-code | 1.270 → 2.073 | +63.3% | 2.380 → 3.968 | +66.7% |
| selection | 10 lines | 0.212 → 0.184 | -13.2% | 0.684 → 0.397 | -42.0% |
| selection | 50 lines | 1.409 → 1.114 | -20.9% | 2.722 → 1.663 | -38.9% |
| selection | 100 lines | 2.356 → 2.219 | -5.8% | 3.238 → 4.170 | +28.8% |
| stress | initial-frame | 348.043 → 338.789 | -2.7% | 348.043 → 338.789 | -2.7% |
| stress | input-burst | 251.996 → 251.143 | -0.3% | 381.505 → 302.847 | -20.6% |
| stress | presentation | 18.923 → 19.309 | +2.0% | 26.692 → 28.212 | +5.7% |
| stress | idle-1000-polls | 0.052 → 0.050 | -4.4% | 0.308 → 0.139 | -55.0% |

## Whole-process CPU cross-check

Linux child-process user + system CPU seconds (getrusage), median of three trials. This excludes time spent descheduled but includes process startup, warmups, all phases and the separate instrumented replay. It is an aggregate CPU cross-check, not a replacement for the per-phase wall-clock samples above.

| Process workload | Baseline CPU seconds | Candidate CPU seconds | Change |
|---|---:|---:|---:|
| layout | 0.175 | 0.170 | -2.4% |
| interactive-layout | 0.176 | 0.185 | +5.4% |
| markdown | 1.645 | 2.104 | +28.0% |
| selection | 0.158 | 0.155 | -2.2% |
| stress | 13.130 | 12.360 | -5.9% |

## Interaction-handle ablation and decision

A separate source copy reverted only interaction handles, retaining the other cleanup. Three default StressBenchmark trials used rotating baseline/handles/no-handles order, CPU3 affinity, and deterministic Swift hashing. Drawing and registration work matched; both candidate variants retained the lower measurement count. No own build or test ran during timing.

| Variant | Whole-process CPU seconds, median | Input-burst p50 ms, median | Presentation p50 ms, median |
|---|---:|---:|---:|
| baseline | 15.723 | 298.895 | 21.760 |
| candidate | 13.868 | 285.908 | 20.908 |
| no-handles | 13.475 | 278.549 | 20.081 |

The no-handles variant used less aggregate CPU than handles in all three trials: 2.9% lower at the median, with substantial variance in the first trial. It also removes 33 more production lines. This supports keeping the smaller cleanup and deferring handles; it does not establish the earlier ~20% slowdown as a stable causal effect. Existing generation checks and distinct render/navigation projections remain, while selection/command state still uses ordinal paths.

Stress work counters improve deterministically versus the base: input-burst measurements 49,388 → 42,320 (−14.3%) and presentation measurements 3,948 → 2,974. Input still paints nothing; node counts, registration counts, drawing commands and zero buffer growth match.

## Earlier measurements retained

The first all-points candidate showed +18.9% stress input-burst p50 and layout regressions amid large trial variance. Removing duplicate navigation indexing improved layout. A second broad grouping still measured +20.1% aggregate stress CPU, +39.0% Markdown and +22.1% selection. Adjacent diagnostics subsequently found Markdown roughly even, selection −10.3%, small/deep stress −11.7%, and large/shallow stress +22.2%. The unchanged large-row scan has identical normalized machine instructions in both binaries.

These inconsistent results prompted the explicit ablation, rather than hiding regressions or claiming universal speedups. All original measurement reports, source/binary hashes, raw trials, p50/p95 summaries, adjacent diagnostics and ablation data are preserved under `investigation` in the JSON. GNU clock profiling warned that its timer had been reset and hardware counters were unsupported; that profile was not used as quantitative evidence.


## Targeted Markdown spike check

The final broad run includes a candidate process with 14.88 CPU seconds / 29.55 elapsed seconds and multi-second frame tails. Four subsequent adjacent baseline/candidate pairs used the same binaries, CPU affinity, hashing, fixtures and command counts, without overlapping builds/tests. No multi-second tail recurred. This check does not erase the adverse trial or prove a universal speedup.

| Variant | Median whole-process CPU seconds | Range seconds |
|---|---:|---:|
| baseline | 1.519 | 1.437–1.838 |
| candidate | 1.446 | 1.375–1.506 |

The selected candidate used 4.8% less median process CPU in this check (1.519 → 1.446 seconds); three of four pairs favored it. Work counters and output counts remained deterministic. The isolated spike was not reproduced, so no additional speculative optimization was made. Raw CPU/wall times, page faults, context-switch counts and every workload result are retained under `markdown_spike_check` in the JSON.

## Scope and reproduction

Default existing workloads were used: LayoutBenchmark and `--interactive` (20 rows; depth 1/3/5; 3 warmup, 20 measured frames), MarkdownBenchmark (200 paragraphs/static/streaming/narrow plus long code; 5 warmup, 30 frames), TextSelectionBenchmark (10/50/100 lines; 5 warmup, 20 frames), and StressBenchmark (default configuration and sampling recorded in JSON).

Build each checkout with `CHROMA_HEADLESS_ONLY=1 swift build --package-path Benchmarks -c release --disable-automatic-resolution -j 2`, then run each executable as `SWIFT_DETERMINISTIC_HASHING=1 taskset -c 3 <executable> [arguments]`, serially in the alternating order above. The installed SwiftPM default build system was used for both. Use the same dependency lockfiles and Swift 6.4 toolchain. CPU affinity and fixed hashing reduce some variability but cannot eliminate shared-host or type-address effects.

These are CPU/headless measurements. Native Metal/Wayland presentation, GPU work and physical input latency were not tested. Stress first-frame timing has one sample per process. Raw-key dispatch is covered by semantic tests rather than this resolved-input benchmark; prior stress numbers are not invalidated by the old headless double-refresh path.
