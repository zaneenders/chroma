# Storage comparison

Run from the repository root with a clean Swift Collections checkout:

```sh
sh Benchmarks/Scripts/storage.sh ../swift-collections
```

The isolated temporary package keeps Swift Collections out of Chroma's dependencies. The script records the checkout revision. Use release builds; preserve hardware, toolchain, and worktree metadata with results.

Both containers append identical 24-byte Nodes, update every value, and traverse every value with matching checksums. Reports separate build/update/traversal p50/p95 over 30 samples after five warmups, with and without reserved capacity. Growth counts are capacity changes during append, not allocation counts. Reservation and destruction are outside timing. Array always runs first; this is a microbenchmark, not an engine-storage decision by itself.

The corrected run used Collections revision `af174fe4476842b2558069e64feae8ddc2e665ff`. At 100,000 nodes without reservation, Array build p50/p95 was 0.455/0.496 ms versus UniqueArray 0.486/0.644 ms (17 versus 29 capacity changes). With reservation, UniqueArray built faster (p50 0.131 versus 0.219 ms), while updates were comparable and Array traversal was faster. Retain Array provisionally; there is no consistent win justifying a new engine dependency.

Results and metadata: `Benchmarks/results/phase1-timing-fix-20261001-003523/` (ignored runtime artifacts). All three test suites passed in this run. Interaction results distinguish content installation from the cold frame and warm input/render batches. Warm render still combines layout and paint. Allocation profiling, engine storage growth/visible-row counters, and separate layout/paint/backend submission measurements remain required before the Phase 1 gate is complete.

Latest fresh release interaction collection: `Benchmarks/results/phase1-fixed-20261001-005011/`, with all 36 cases and revision/worktree, toolchain, and hardware metadata. Examples (53 tests) and Benchmarks (3 tests) passed after fixing the fixture's missing `@BlockBuilder`; core (390 tests) passed before these fixture-only changes. The 30-second Allocations recording failed to attach to the target, so its trace is invalid. No recording or benchmark process was left running. Keep the Phase 1 gate open until the remaining measurements above are collected.

## Revised Phase 1 gate: baseline-ready (Linux)

The revised bounded gate supersedes the historical open-gate requirements above. Fresh evidence: `Benchmarks/results/phase1-linux-final-20261001-012520/`. Core: 391 tests; Examples: 54; Benchmarks: 3; watchdog/profile-validation tests: 2. Linux x86_64, i5-12600KF, Swift 6.4 release. The source archive includes untracked diagnostic sources; resolved dependencies, build flags, hardware, stage statuses, logs, and raw/converted profiles are retained there. The earlier `phase1-linux-20261001-012000` run is superseded, not pooled.

Three unprofiled trials, diagnostics off: 1,000 rows, eight events/frame, 400×600, five warmups, 30 measured frames. Median across trials of each trial's percentiles, milliseconds (input is a batch):

| Layout / workload | Input p50 | Input p95 | Render p50 | Render p95 |
|---|---:|---:|---:|---:|
| eager pointer | 0.017 | 0.019 | 15.230 | 15.724 |
| eager scroll | 122.282 | 125.268 | 15.186 | 15.904 |
| eager drag | 126.746 | 129.222 | 15.813 | 16.335 |
| lazy pointer | 0.007 | 0.007 | 0.097 | 0.101 |
| lazy scroll | 0.754 | 0.771 | 0.099 | 0.104 |
| lazy drag | 0.805 | 0.817 | 0.103 | 0.107 |

Separate diagnostic run, case totals including installation/cold/warmups and drag press (release is after printing):

| Layout / workload | Bodies | Registration passes | Primitive visits | Lazy row visits | Focus capacity growth |
|---|---:|---:|---:|---:|---:|
| eager pointer | 37 | 37 | 37,148 | 0 | 481 |
| eager scroll | 317 | 317 | 318,268 | 0 | 4,121 |
| eager drag | 319 | 319 | 320,276 | 0 | 4,147 |
| lazy pointer | 37 | 37 | 1,702 | 814 | 222 |
| lazy scroll | 317 | 317 | 14,652 | 7,009 | 1,901 |
| lazy drag | 319 | 319 | 14,674 | 7,018 | 1,913 |

Fixture warm counts: eager scroll/drag input draws 8,000 and measurements 24,000 per batch, render draws 1,000 and measurements 3,000; lazy input draws 176, render 22, measurements zero (fixed-height rows). Pointer input does no fixture work. Engine body counts cover `BlockEngine.resolve`; registration counts cover drawing registrations, including render. Primitive visits cover `drawResolved`, including registration-only draws, not every modifier wrapper or exclusively painting. Lazy visits cover the visible draw and focus-buffer loops. Capacity counts cover focus-node child arrays, not all arrays or allocations. Enabled counters add branches and writes; disabled counters still have branch overhead. Compare candidates with identical settings, not historical always-counted fixtures.

Both scroll profiles contain 500 UI-thread samples and recognizable Chroma frames, from separate 30-second replays with 500 samples at 10 ms. Eager: `BlockEngine.resolve` in 330/500 stacks, `VStack.draw` 223, `sizeThatFits` 173; lazy: `ScrollView.draw` 412, resolve 132, dictionary-related frames 141. Retain/release and dynamic casts are prominent; lazy stacks also show WidgetID hashing/lookup. These are overlapping inclusive occurrences, **not exclusive CPU percentages**. Each capture contains about 18,400 thread samples: most are waiting NIO/Dispatch threads (epoll/condition waits), not UI work. Every UI stack contains at least one unresolved frame, although useful engine frames are resolved; validation logs also report unresolved frame totals. Follow-up: improve Swift runtime/async-entry symbol coverage before attributing those frames. `.perf` files can be opened in Speedscope or Firefox Profiler.

Release uses `-Xswiftc -g`; emitted build logs include toolchain-provided `-Xcc -fno-omit-frame-pointer`, which is not claimed to configure Swift frame pointers. Recognizable Swift stacks were verified empirically. Sampling and symbolication overhead are not quantified; profiled timings are excluded. No allocation, exact layout/paint, backend/GPU, macOS, or expanded 100/5,000-row claim is made. Headless submission is not-applicable. All owned processes were reaped and their sockets removed. Phase 2 may proceed; retain Array provisionally.
