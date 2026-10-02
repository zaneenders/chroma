# Retained-only runtime validation

The final VirtualListBenchmark release replay completed 72 cases (three trials, fixed/variable lists, 1,000/100,000/1,000,000 items, pointer/scroll/drag/streaming, eight events per frame, five warmups, 30 measured frames, 400×600). No lifecycle opt-in exists; these results exercise the default runtime. Warm pointer row builders remain zero and input dispatch performs no paint. Source and workload configuration are recorded by this commit; toolchain/host match the phase6-engine collection (Swift 6.4/Linux, Intel i5-12600KF).

Build/test/replay deadlines: tests 300s/package, release build 600s, replay 120s, TERM then five-second forced cleanup. All completed successfully. These are headless work/latency checks, not GPU or input-to-presentation measurements. Sampling and allocation evidence remain deferred; no new claim closes the broader Phase 6 profiling gate.

`BlockEngine` direct-draw APIs still exist for legacy standalone measurement/drawing tests and API callers, but neither WindowRuntime nor NodeFrameProducer invokes them. The old frame producer is test-only as a differential oracle. Runtime fallback, registration-through-discarded-draw, producer selection, and opt-in flags are removed. Full deletion of the public direct-draw DSL methods is a separate source-breaking API cleanup, not a second engine used by hosts.
