# Phase 4 virtual lists

Run: `swift run --package-path Benchmarks -c release VirtualListBenchmark`

One Linux release trial, 400×600 viewport, five warmups, 30 measured frames, eight unchanged pointer events per frame. Each case jumps far into history before warm measurement. Variable rows contain wrapped messages of varying lengths. Snapshot construction is reported separately; it is intentionally O(collection size).

All cases built zero rows during warm frames. Fixed-height warm p95 was 0.23–0.46 ms; variable-height warm p95 was 0.09–0.10 ms. Results are headless input-plus-render latency, not GPU measurements or a baseline comparison. A single trial is not sufficient for statistical performance claims. Changed-content/streaming timing and scroll/drag trial matrices remain pending.

`metadata.txt` records the parent revision and machine/toolchain. The candidate adds the sources committed with this report. `timings.csv` contains raw per-case summaries.
