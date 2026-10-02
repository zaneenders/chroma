# Chroma Benchmarks

Run commands from the repository root. Use release builds and consistent hardware, toolchain, and workloads when comparing results.

## Input frames

```sh
swift run --package-path Benchmarks -c release InputFrameBenchmark
```

Measures the headless rendering path through `ChromaTesting.HeadlessHost` for scrolling lists with 1,000, 100,000, and 1,000,000 items, with and without explicit identity. Prints one cold and five warm frame timings per case:

- `replace-root` constructs and replaces the root before every render. `setup` includes construction and replacement; `render` includes registration and drawing. Even warm iterations reset the interaction tree.
- `deferred-root` keeps a `DeferredBlock` installed, as an app does, and constructs its list during traversal. Warm iterations keep the interaction tree. List construction is included in `render` and can occur more than once per input frame.

These timings exclude native input dispatch, scheduler waits, Metal encoding, and GPU execution. They are not consumed by `CompareBenchmarks`.

## Nested layout

```sh
swift run --package-path Benchmarks -c release LayoutBenchmark
swift run --package-path Benchmarks -c release LayoutBenchmark --interactive
```

Measures 20 session-style rows in a scroll view under one, three, or five layers of groups and stacks. Each case warms up for three frames and reports 20 frames as JSON: p50/p95 time, body evaluations per frame, and draw-command count. `none` explicitly renders without input; it does not measure application idle CPU. `scroll` includes input registration and the resulting frame. These reports are not consumed by `CompareBenchmarks`.

`--interactive` wraps each layer in a control. Its idle measurement tree is shared within a traversal, while painting builds the current interaction phase with the control's child focus context. This adds work per nested control without repeating every idle layout query.

Increasing container depth must not multiply row-body evaluations. The prepared layout tree gives each built-in container ownership of its resolved children, sharing them across expansion checks, measurement, and drawing. Each resolved node memoizes sizes by proposal for that traversal only. A new traversal evaluates current state and reinstalls observation tracking. Custom primitives remain boundaries using their existing measurement/drawing methods; phase-dependent controls still build the appropriate appearance at draw time.

`StackEvaluationTests` covers nested body counts, repeated and changed proposals, fresh state between traversals, and scroll-content reuse without relying on timing thresholds:

```sh
swift test --filter StackEvaluationTests
```

## How an input reaches the screen

1. The backend snapshots native input and queues it on the main actor.
2. `WindowRuntime` applies events in order. Clicks, dragging, scrolling, commands, and text edits first rebuild registrations to obtain current callbacks and hit-test geometry. Plain hover uses the last frame's geometry.
3. `FrameScheduler` coalesces requests and caps frame starts at `maximumRefreshRate` (60 Hz by default). Rendering time counts toward that interval. With no requests or Wayland scroll momentum, it schedules nothing.
4. `FrameProducer` evaluates the deferred body, measures and draws blocks, builds the interaction tree, and tracks observable properties. A change to a tracked property requests another frame.
5. The backend culls and encodes the draw commands, then submits them to the GPU.

Registration refresh currently traverses and draws the UI into a discarded command list. Coalescing presentation therefore does not eliminate the CPU work for each actionable input event. Virtualized lists build visible rows, but identified list construction still scans every element's ID; a small command count does not imply cheap construction.

The remaining architectural work is to separate layout and hit-test registration from painting, retain them with explicit invalidation, and update only affected subtrees. Geometry, current action closures, text-editing state, and structural identity must all stay current before dispatching input; simply skipping registration refresh would break that contract. Identified collections also need explicit revisions or change sets before their ID scans can safely be skipped.

The scheduler and hover regressions are covered without wall-clock performance thresholds:

```sh
swift test --filter 'FramePacingTests|WindowRuntimeTests|FrameSchedulerTests'
```

`FramePacingTests` simulates rendering costs to check frame deadlines. `WindowRuntimeTests` checks hover traversal counts, ordered input, fresh callbacks and text layout, and return to idle after observation delivery. These tests do not measure native presentation smoothness.

## Rendering

```sh
swift run --package-path Benchmarks -c release RenderBenchmark --scene scrolling --stage cull
```

Measures draw-command culling using render fixtures, not end-to-end view rendering. On macOS, `--stage metal` also measures CPU Metal encoding and GPU execution. Reports JSON with cold timings and warm timing distributions.

Use `--help` for scenes and measurement options.

## Profiling ShapeTree on macOS

ShapeTree's desktop package uses the neighboring Chroma checkout. Build optimized code with symbols, then record the actual app:

```sh
swift build --package-path ../shape-tree/apps/shape-tree-desktop \
  -c release -Xswiftc -g --disable-automatic-resolution --product ShapeTreeDesktop
profile_dir=$(mktemp -d /tmp/shape-tree-profile.XXXXXX)
xcrun xctrace record --template 'Time Profiler' --time-limit 60s \
  --output "$profile_dir/time-profiler.trace" --launch -- \
  "$PWD/../shape-tree/apps/shape-tree-desktop/.build/release/ShapeTreeDesktop"
open -a Instruments "$profile_dir/time-profiler.trace"
```

Interact with the launched window during the capture. The recorder terminates its launched process at the time limit; a saved trace can accompany a nonzero exit status. Keep the binary and matching dSYM available for symbolication. Compare the same workload, separating idle, input registration, layout/body evaluation, and renderer costs. Inclusive stack times overlap and must not be added together. Manual captures locate bottlenecks; use deterministic benchmarks to claim speedups.

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
