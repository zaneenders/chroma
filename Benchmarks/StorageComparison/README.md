# Storage comparison

Run from the repository root with a clean Swift Collections checkout:

```sh
sh Benchmarks/Scripts/storage.sh ../swift-collections
```

The isolated temporary package keeps Swift Collections out of Chroma's dependencies. The script records the checkout revision. Use release builds; preserve hardware, toolchain, and worktree metadata with results.

Both containers append identical 24-byte Nodes, update every value, and traverse every value with matching checksums. Reports separate build/update/traversal p50/p95 over 30 samples after five warmups, with and without reserved capacity. Growth counts are capacity changes during append, not allocation counts. Reservation and destruction are outside timing. Array always runs first; this is a microbenchmark, not an engine-storage decision by itself.

The corrected run used Collections revision `af174fe4476842b2558069e64feae8ddc2e665ff`. At 100,000 nodes without reservation, Array build p50/p95 was 0.455/0.496 ms versus UniqueArray 0.486/0.644 ms (17 versus 29 capacity changes). With reservation, UniqueArray built faster (p50 0.131 versus 0.219 ms), while updates were comparable and Array traversal was faster. Retain Array provisionally; there is no consistent win justifying a new engine dependency.

Results and metadata: `Benchmarks/results/phase1-timing-fix-20261001-003523/` (ignored runtime artifacts). All three test suites passed in this run. Interaction results distinguish content installation from the cold frame and warm input/render batches. Warm render still combines layout and paint. Allocation profiling, engine storage growth/visible-row counters, and separate layout/paint/backend submission measurements remain required before the Phase 1 gate is complete.
