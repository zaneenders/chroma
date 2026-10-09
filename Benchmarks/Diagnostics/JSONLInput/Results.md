# JSONL input transport results

Measured 2026-10-09, Swift 6.4 release compiler, Linux x86_64, `-O -swift-version 6 -warnings-as-errors`.
Baseline: main `7d9012c3c7de72605f77d3ffce301924365b6192`.
The same driver compiled separately with each actual reader source. Other task builds
and benchmarks were paused for the measurement window. Shared-cloud timing noise
remains; these are diagnostics, not statistical significance or CI thresholds.

Two runs per implementation in baseline / buffered / buffered / baseline order.
Each run discards one warmup and records five samples per workload. The table gives
median (minimum–maximum) **milliseconds per whole workload** across all 10 samples.
Every line/status and EOF validator passed. All 80 measured samples are preserved
in [samples.jsonl](samples.jsonl); no samples were discarded.

| Workload | Byte-at-a-time baseline | Buffered reader |
| --- | ---: | ---: |
| short-burst | 341.251 (314.110–384.740) | 2.833 (1.839–5.198) |
| short-handshakes | 83.655 (64.337–96.885) | 49.698 (32.743–77.395) |
| maximum-length | 1624.374 (1548.295–1845.871) | 7.706 (5.338–10.195) |
| oversized | 1773.234 (1594.426–2354.759) | 4.915 (3.601–6.855) |

Short bursts contain 10,000 requests; handshakes contain 1,000; maximum-length
contains 32 requests of 65,536 bytes; oversized contains eight 262,144-byte lines.
See [method and reproduction](README.md). Timings include pipe producer scheduling,
framing and validation, but **exclude JSON decoding, session scheduling, rendering,
response encoding and native/GPU work**. They support reduced framing overhead,
not equivalent full-application speedups or measured syscall/allocation counts.
Handshake results are more scheduler-sensitive than burst throughput.

## Source and binary SHA-256

- baseline reader: `36754d94f4fdc1b14625b6d33e0cc373264f0c7e16ae49f327a51ba27f2a5395`
- buffered reader: `b955ae035c8695d9b534b310c97900d5438389e4b1118426586fa886b15d4719`
- shared driver: `1bb4d0102a882753f78ae8c2a26f07999109318f5818769eb6df3db3fee7102b`
- baseline binary: `f42df7a4c35caf3f8010e0af0e3330f53cb6fec47c98635d34b0982c71e35bf2`
- buffered binary: `7e54d1648cf8ae5cd6e2bdf4f0c3fc96b1338af4c55fde8ae3373767862b8e13`

## Correctness validation

- All 555 root Swift tests passed, including seven new bounded-reader tests.
- All 18 headless child-process tests passed, including two new transport tests.
- Open-stdin delivery, incomplete lines, split UTF-8, limits, burst ordering,
  oversized/invalid-UTF8 recovery, EOF, cancellation and child reaping are covered.
- Strict formatting, shell syntax and whitespace checks passed.
- Two independent static reviews found no production blockers.
- Linux only; macOS execution was not available. EINTR retry is source-reviewed,
  while the new deterministic error-path test checks EBADF rather than injecting signals.

## Integration watchdog follow-up

The local combined follow-on tree (`2088aa9be0a6ef28d1fc0e38890c18ba585de357`)'s
existing 256-response debug pipe-draining test reached
the original 10-second session deadline. A diagnostic 30-second guard let it finish
with every functional assertion passing in 10.056 seconds. Restoring the previous
font diagnostics and byte-at-a-time reader from `a8ab7bd` in that same combined
fixture (only `HighResolutionFontAtlas.swift`, `MissingGlyphWarnings.swift` and
`BoundedLineReader.swift` restored) yielded
9.875 seconds, also close to the cutoff. These single shared-host samples establish
an inadequate watchdog margin, not a production speedup or non-regression claim.

Only that functional burst test now opts into a 30-second finite session watchdog;
other session defaults remain 10 seconds. No burst-size, ordering, EOF or response
assertions were removed. A new one-second custom-session timeout regression checks
cancellation and child reaping, with an eight-second outer assertion that detects an
ignored override without imposing a tight cleanup-performance budget. This test-only
follow-up does not change the reader or the transport benchmark samples above.
