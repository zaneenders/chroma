# Phase 4 virtual lists

Build: `swift build --package-path Benchmarks -c release --product VirtualListBenchmark`
Run the freshly built binary with a 120-second external timeout.

Three Linux release trials, 400×600 viewport, five warmups, 30 measured frames, eight ordered events per frame. Each case jumps far into history before measurement. Sizes: 1,000, 100,000, 1,000,000 rows. Workloads: pointer, scroll (eight one-point deltas), drag (pressed pointer movement), streaming (one observed message update per frame). Variable rows contain wrapped messages of varying lengths. Fixed streaming cases are unchanged controls. Snapshot construction is reported separately and intentionally O(collection size).

All pointer and drag cases built zero warm rows. Across sizes/trials, fixed pointer p95 was 0.23–0.27 ms and variable pointer p95 0.09–0.10 ms. Fixed scroll built 780 rows per 30 frames regardless of collection size (visible-range changes rebuild the viewport); variable scroll built 13–16. Variable streaming built 34–36 rows. Scroll p95 was 1.10–1.20 ms fixed and 0.33–0.43 ms variable; variable streaming p95 was 0.12–0.16 ms. Work tracks viewport/changed content, not total history. These are headless input-plus-render timings, not GPU measurements or a baseline comparison. Drag benchmarks measure delivered pointer motion; editor drag correctness is covered separately by core tests.

`metadata.txt` records the parent revision and machine/toolchain. The candidate adds the sources committed with this report. `timings.csv` contains all 72 per-case summaries. No profiler or allocation claims are made.
