# Markdown operation-local preparation results

Measured 2026-10-09 on Linux x86_64, Swift 6.4 release builds. Baseline: `7d9012c3` with only this PR's benchmark fixture/target added. Candidate: this PR's Markdown preparation changes. The harness and source inputs were identical. Two serial baseline/candidate pairs were run with other project builds/tests/benchmarks paused; this is a shared cloud host, not an isolated performance lab.

Each process used five warmups and 30 samples per case. Instrumentation was disabled for timings and enabled for a separate final-sample replay. The percentile definition is lower median and nearest-rank p95. Values are milliseconds; both trials are reported rather than choosing the best one.

| Workload | Source bytes | Width | Commands (both) | Baseline p50 / p95, trial 1 | Candidate p50 / p95, trial 1 | Baseline p50 / p95, trial 2 | Candidate p50 / p95, trial 2 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| static | 17888 | 500 | 16095 | 39.35 / 53.21 | 19.03 / 25.26 | 31.04 / 41.18 | 19.00 / 25.64 |
| streaming | 17932 | 500 | 16137 | 68.20 / 111.24 | 32.80 / 38.04 | 70.22 / 100.90 | 32.26 / 35.72 |
| narrow | 17888 | 36 | 15195 | 37.54 / 48.96 | 20.93 / 25.24 | 35.94 / 56.12 | 20.26 / 22.84 |
| long-code | 8013 | 120 | 8805 | 28.73 / 32.10 | 7.48 / 8.94 | 28.01 / 38.90 | 8.42 / 15.19 |

The static, narrow, and long-code cases retain their root. Streaming replaces it with a growing incomplete Markdown tail each sample, including root replacement in the timer. All timings include document segmentation, layout, registration and command generation together. They do not isolate parsing, do not include native/GPU presentation, and do not imply a frame-rate guarantee. A first trial containing an unsupported emoji was discarded because synchronous missing-glyph logging (#99) distorted the measurement. The final fixture uses supported glyphs; all four final process stderr captures were empty.

## Deterministic work and correctness

- A matching leaf measurement, registration, and two paints build exactly **one** layout/inline-parse result. The previous implementation unconditionally ran `layoutMarkdown` at each of the three phase entry points. Height-only proposal changes and origin/same-column-width placement changes reuse shaping.
- Changed block, columns, theme, scale, font metrics, spacing, and leading gap replace the single cache entry. Returning to an older key rebuilds it; no history is retained.
- Registered callbacks retain value snapshots after cache replacement and release the mutable preparation when the operation ends. New operations install fresh text. The prepared wrapper preserves the original engine-scoped leaf identity and primitive focus behavior.
- Registration emits no paint commands; painting creates no registrations. Snapshot command-equivalence tests cover mixed blocks, Unicode graphemes, tables, incomplete markup, and narrow widths. Existing selection/copy/navigation and streaming-table regressions remain in the full suite.
- The separate metric replays had identical baseline/candidate counts: static/narrow each 603 measurement requests, 203 registrations, 203 paints and peak 203 resolved nodes; streaming 1,212 / 408 / 204 and peak 204 nodes; long-code 6 / 4 / 4 and peak 4 nodes. No extra resolved node is introduced per leaf. All cases finished the measured operation with zero live resolved nodes.

## Validation

The final Linux root suite passed **557 tests** (including 25 Markdown and 479 core tests). The benchmark package aggregate suite passed **7 tests**. Strict formatting lint and `git diff --check` passed. Native dependency setup used Wayland 1.26 headers/libraries; these results do not include macOS or a physical-display session.

## Reproduction

```sh
swift test
swift run --package-path Benchmarks -c release MarkdownBenchmark
```

Use the same `Benchmarks/Package.swift`, lockfile, and `Benchmarks/Sources/MarkdownBenchmark/main.swift` on the baseline revision to reproduce the comparison. Run release executables serially after builds finish. No hard wall-clock threshold is added to CI. Parsed-document reuse across operations, offscreen semantic-block virtualization, and long-line wrapping improvements remain separate work under #96.
