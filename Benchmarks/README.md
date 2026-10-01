# Chroma Benchmarks

Run commands from the repository root. Use release builds and consistent hardware, toolchain, and workloads when comparing results.

## Input frames

```sh
swift run --package-path Benchmarks -c release InputFrameBenchmark
```

Measures the headless rendering path through `ChromaTesting.HeadlessHost` for scrolling lists with 1,000, 100,000, and 1,000,000 items, with and without explicit identity. Prints one cold and five warm frame timings per case. These timings are not consumed by `CompareBenchmarks`.

## Rendering

```sh
swift run --package-path Benchmarks -c release RenderBenchmark --scene scrolling --stage cull
```

Measures draw-command culling using render fixtures, not end-to-end view rendering. On macOS, `--stage metal` also measures CPU Metal encoding and GPU execution. Reports JSON with cold timings and warm timing distributions.

Use `--help` for scenes and measurement options.

## Baselines and comparisons

Collect all scenes, or select scenes with `SCENES`. Set `METAL=1` on macOS to include Metal measurements.

```sh
Benchmarks/Scripts/run.sh Benchmarks/results/run
SCENES="scrolling selection" METAL=1 Benchmarks/Scripts/run.sh Benchmarks/results/metal

Benchmarks/Scripts/baseline.sh Benchmarks/results/baseline 5
# After making changes, collect the same workloads into a new directory.
Benchmarks/Scripts/baseline.sh Benchmarks/results/candidate 5
swift run --package-path Benchmarks -c release CompareBenchmarks \
  Benchmarks/results/baseline Benchmarks/results/candidate --max-regression-percent 15
```

The scripts preserve reports and revision, worktree, toolchain, dependency, and hardware metadata. `run.sh` refuses nonempty output directories; `baseline.sh` requires a new directory and accepts 3–30 trials (default: 5). Keep old baselines and create new directories when updating them.

Dependency metadata comes from `swift package show-dependencies --format json`; no `Package.resolved` is required. Build and metadata collection complete before a results directory is created. Keep generated reports under the ignored `Benchmarks/results/` directory.

Comparisons require matching workloads, configuration, toolchain, dependencies, and hardware. They compare median p50/p95 timings across trials and exit nonzero for regressions above the threshold (default: 15%). Reported spread is not a confidence interval.

## Testing

```sh
swift test --package-path Benchmarks
```

## Interaction rebuilding

```sh
swift run --package-path Benchmarks -c release InteractionBenchmark
```

Exercises the backend input path through `HeadlessHost.handleInput()` followed by `renderScheduled()`, without Metal. Content is installed once. Compares eager and lazy interactive lists with 100, 1,000, and 5,000 rows, sending one or eight pointer, scroll, or held-drag events before each rendered frame. Scroll deltas alternate direction between frames to avoid measuring only a clamped boundary. Drag press/release setup is outside the timed batches. Uses five warm-up frames and 30 measured frames per case.

Reports separate input-batch and render p50/p95 milliseconds, plus average row draw calls per frame for each phase. Input times are per batch, not per event. Row draw counts reveal registration rebuilds even when timing varies. Pointer movement reuses valid registrations; scrolling and dragging still use conservative refreshes. This output is not consumed by `CompareBenchmarks`.

Interaction reports also include content installation and cold-frame timings at a 400×600 viewport, plus fixture row measurements and workload body evaluations. These are not engine-wide counters; row draws combine registration and painting work, and warm render combines layout and paint.

For profiling, stop on failed builds (`set -e` or `&&`) before launching the freshly built release executable. Use `xctrace record --template Allocations --time-limit 30s --output NEW_TRACE_PATH --launch -- EXECUTABLE`. Check the exit status and recording log: a saved trace with attach errors is not a valid allocation profile.
