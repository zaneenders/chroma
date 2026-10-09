# Bounded missing-glyph diagnostics (#99)

## Scope and contract

The default deliberately changes from synchronous per-occurrence stderr writes to bounded,
asynchronous diagnostics. Each shared/scoped diagnostics instance reports at most 64 distinct
scalar-prefix signatures plus one suppression notice, for its lifetime. Signatures retain at most
16 Unicode scalars plus a truncation marker. This caps both memory and pending log records even
for very long grapheme clusters and many-distinct input. After the limit is exceeded, reporting
returns before extracting scalar metadata. Codepoint-only privacy and fallback UVs are preserved.

Environment and explicit per-atlas policy/sink configuration are documented in
[ChromaFont](../Sources/ChromaFont/README.md). `verbose` preserves full per-occurrence detail but is
explicitly unbounded; `off` disables reporting. Background delivery is best effort at process exit.
No time-based resets or hidden repeated-warning counters grow over the process lifetime.

## Measurements

Swift 6.4 release, Linux x86_64, 2026-10-09. Baseline main
`7d9012c3c7de72605f77d3ffce301924365b6192`; identical fixture on baseline and the bounded implementation.
Three alternating baseline/fix trials per scenario, fresh process per trial, 200,000 actual
`HighResolutionFontAtlas.glyphUV` lookups. Repeated input is the unsupported wave emoji; distinct
input cycles over 256 private-use scalars. Stderr goes to a regular temporary file. Atlas loading
is outside the measured lookup region. Every trial produced the same UV checksum, `711576.7`.

| Scenario | Baseline median lookup ms | Bounded median lookup ms | Baseline stderr | Bounded stderr |
| --- | ---: | ---: | ---: | ---: |
| Repeated character | 342.32 | 51.95 | 200,000 lines / 11,000,000 bytes | 1 line / 55 bytes |
| 256 distinct characters | 417.08 | 35.69 | 200,000 lines / 11,000,000 bytes | 65 lines / 3,596 bytes |

All trials, including process user+system CPU time, are retained in
[MissingGlyphResults.json](MissingGlyphResults.json). No slow trials were discarded. Bounded lookup
latency excludes final asynchronous sink delivery; total child CPU includes it, startup and atlas
loading. The fixture waits 200 ms outside the timed region to let bounded output finish, and the
runner verifies exact line counts. These diagnostic samples have shared-host variance and are not
statistical confidence intervals, whole-frame speedups, native FPS or physical-display claims.

The independent unconsumed-stderr-pipe probe leaves stderr unread until child exit. Baseline filled
the pipe (65,120 bytes), produced no completed lookup result within two seconds, and was terminated
by the probe. The bounded version exited normally after all 200,000 lookups with 55 bytes of output.
The regression suite also holds an injected sink blocked while thousands of distinct lookups
complete, covering a stalled writer even when the sink cannot accept a single record.

Measured binary SHA-256:
- Baseline: `1e4ee07c277aa9aa794ba336528350518b4da53fe4f3adb47ce67fc8756250e7`
- Bounded: `4ad8dd733721217c0977e7445501b67edf4f9753305cec640d041a7464e5e430`

## Reproduction

Build this branch's benchmark and a baseline worktree with the exact same benchmark package target
and source copied into it. The fixture deliberately only uses the baseline atlas API.

```sh
swift build --package-path Benchmarks --scratch-path /tmp/glyph-fixed -c release -j 2 --product MissingGlyphBenchmark
# In the baseline worktree after copying the fixture and its target entry:
swift build --package-path Benchmarks --scratch-path /tmp/glyph-baseline -c release -j 2 --product MissingGlyphBenchmark
# Back in this branch:
python3 Benchmarks/Scripts/missing-glyph.py /tmp/glyph-baseline/release/MissingGlyphBenchmark /tmp/glyph-fixed/release/MissingGlyphBenchmark
```

The runner removes the diagnostic-policy environment override, retains every timing, checks
lookup counts/checksums/log volume, and terminates a blocked-pipe child after its explicit two-second
observation window. The expected baseline is the synchronous implementation, not verbose mode on
the new asynchronous implementation.

## Validation

- Full root suite: 557 tests passed, including 11 missing-glyph tests (9 added).
- Concurrent duplicate and many-distinct requests, saturation, bounded long-grapheme metadata,
  exact-versus-truncated signatures, full verbose detail, disabled policy, configuration defaults,
  stalled sinks, and identical fallback/supported UVs are covered.
- Release baseline/fixed benchmark builds, strict Swift formatting and whitespace checks passed.
- Two independent static reviews found no blockers.
- Linux native dependencies were staged for the root suite. macOS/Metal and interactive native
  display rendering were not executed; diagnostic backpressure tests do not claim that validation.
