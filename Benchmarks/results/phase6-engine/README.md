# Retained text-layout comparison

Baseline: `e8519dc`, exported with `git archive` into a temporary directory named `chroma` so SwiftPM preserves package identity. Candidate: engine changes in this commit. Both freshly built with `swift build --package-path Benchmarks -c release`, then run unprofiled with a 120-second external deadline. Each CSV contains three trials of 24 cases: fixed/variable lists, 1,000/100,000/1,000,000 items, pointer/scroll/drag/streaming, eight events per frame, five warmups, 30 measured frames, 400×600 viewport. Diagnostics are unchanged. Snapshot installation is separate from warm frame timings.

Host: Intel Core i5-12600KF, Linux x86_64 7.2.3-arch1-3, Swift 6.4 release. Resolved dependencies are in `dependencies.json`; source patch and command logs are retained beside the CSV files. Collection ran without concurrent build/test workloads. The first baseline build failed because the temporary directory changed SwiftPM identity; one retry using a `chroma` child directory succeeded.

Medians of case p50/p95 values across collection sizes and trials (milliseconds):

| Kind/workload | Before p50 | After p50 | Before p95 | After p95 |
|---|---:|---:|---:|---:|
| Fixed pointer | .250 | .260 | .252 | .263 |
| Fixed scroll | .908 | .907 | 1.158 | 1.156 |
| Fixed drag | .257 | .265 | .267 | .274 |
| Variable pointer | .103 | .109 | .108 | .111 |
| Variable scroll | .344 | .335 | .411 | .404 |
| Variable drag | .108 | .108 | .111 | .113 |
| Variable streaming | .149 | .134 | .156 | .137 |

Variable streaming improves about 10% in this run; pointer timings slightly regress. This is not a universal speedup claim. Warm row-build counts are unchanged: zero for pointer/drag, 780 for fixed scroll, 13–16 for variable scroll, 34–36 for variable streaming. Collection size does not multiply warm work.

The measured optimization shares a bounded two-entry TextLayout cache between wrapped Text measurement and placement; a regression test verifies two builds over alternating widths, instead of independently building during both passes. Paint and unchanged input reuse the retained layout.

Sampling, allocation profiling, actual application transcript profiling, GPU submission, and input-to-presentation latency were not collected here. Headless frame timing is not presentation latency. Follow-up: capture a bounded retained-transcript replay with the existing profile-recorder tooling and validate actual backend presentation on a configured display host. Phase 6 remains open for those measurements.
