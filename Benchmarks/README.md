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
Benchmarks/Scripts/run.sh Benchmarks/results
SCENES="scrolling selection" METAL=1 Benchmarks/Scripts/run.sh Benchmarks/metal-results

Benchmarks/Scripts/baseline.sh Benchmarks/baseline 5
# After making changes, collect the same workloads into a new directory.
Benchmarks/Scripts/baseline.sh Benchmarks/candidate 5
swift run --package-path Benchmarks -c release CompareBenchmarks \
  Benchmarks/baseline Benchmarks/candidate --max-regression-percent 15
```

The scripts preserve reports and revision, worktree, toolchain, dependency, and hardware metadata. `run.sh` refuses nonempty output directories; `baseline.sh` requires a new directory and accepts 3–30 trials (default: 5). Keep old baselines and create new directories when updating them.

The scripts currently require `Benchmarks/Package.resolved` to copy dependency metadata. If it is absent, collection stops at that step.

Comparisons require matching workloads, configuration, toolchain, dependencies, and hardware. They compare median p50/p95 timings across trials and exit nonzero for regressions above the threshold (default: 15%). Reported spread is not a confidence interval.

## Testing

```sh
swift test --package-path Benchmarks
```
