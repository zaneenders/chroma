# Chroma Benchmarks

Run commands from the repository root. Use release builds and consistent hardware, toolchain, and workloads when comparing results.

## Stress lab benchmark and native example

```sh
swift run --package-path Benchmarks -c release StressBenchmark
swift run --package-path ../chroma-examples -c release StressExample
# Increase collection scans, nesting, and input burst size:
swift run --package-path Benchmarks -c release StressBenchmark \
  --rows 1000000 --panes 4 --depth 12 --events 24 --samples 30 --warmup 5
swift test --package-path Benchmarks --filter StressFixturesTests
```

Both products share `StressScene`: by default three independent virtualized lists,
100,000 identified rows per pane, eight nested interactive layers per visible row,
text previews, and buttons in a 1440×900 viewport. In the native example, scroll
individual panes and click **Update all panes** to invalidate their displayed revision.
The example uses the default configuration; edit its `StressConfiguration` to scale it.

The benchmark accepts the options above (`--help` prints defaults). Each cycle applies
two header activations and an ordered burst of 12 scroll events distributed across
panes, then presents once and checks 1,000 idle polls. Alternating scroll directions
keep the workload near the populated viewport rather than running to an endpoint.
Callbacks must stay fresh and presentation must not replay actions.

JSON separates first-frame, input-burst, presentation, and idle timings and includes
pipeline counters. The initial frame has **one fresh-host sample**, excluding scene
allocation; its p50/p95 are therefore the same, not a startup distribution. Active
phases use 5 warmups and 30 measured cycles by default. Percentiles use nearest-rank
p95 and the lower median. Counters come from the final cycle of a separate matching
replay with instrumentation enabled; timings disable instrumentation. Close checks
that resolved nodes and observation subscriptions are released.

This intentionally stresses whole-collection ID scans as well as visible layout:
virtualization does not eliminate metadata scanning. Timings exclude native event
loops, GPU work, and refresh deadlines. `run.sh` includes `stress-headless.json`
in every collection; `CompareBenchmarks` checks its workload, viewport, schema/fixture
versions, warmup and sample counts before comparing each phase’s p50/p95.
The single-sample first-frame phase is also compared, but is noisier than steady state.
Use the native example for manual profiling, not as evidence of frame-rate guarantees.

`PipelineMetrics.isEnabled = true` starts an opt-in capture. `PipelineMetrics.reset()` clears work counters and resets peaks without hiding currently live objects; `PipelineMetrics.snapshot` reads results. Disabling avoids recording and lifetime-token allocations. Resolved block values and their ordinary proposal caches remain **traversal-scoped**. No cross-frame subtree geometry cache is retained. `drawingCommands` counts engine/frame entry points, not unrelated direct `DrawList` construction, and `measurements` includes cache hits. `placements` counts resolved-node visits with an assigned rectangle rather than distinct constraint-solver operations. Run release timings only when other builds, tests, and profiling processes are idle.

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

`--interactive` wraps each layer in a control. Its idle measurement tree is shared within a traversal, while registration builds the current interaction phase with the control's child focus context and painting consumes that prepared child. This adds work per nested control without repeating every idle layout query.

Increasing container depth must not multiply row-body evaluations. The prepared layout tree gives each built-in container ownership of its resolved children, sharing them across expansion checks, measurement, and drawing. Each resolved node memoizes sizes by proposal for that traversal only. A new traversal evaluates current state and reinstalls observation tracking. Custom primitives explicitly register and paint prepared children. Phase-dependent controls prepare the current appearance during update.

`StackEvaluationTests` covers nested body counts, repeated and changed proposals, fresh state between traversals, and scroll-content reuse without relying on timing thresholds:

```sh
swift test --filter StackEvaluationTests
```

## How an input reaches the screen

1. The backend snapshots native input and queues it on the main actor.
2. `WindowRuntime` applies events in order. Clicks, dragging, scrolling, commands, and text edits first rebuild registrations to obtain current callbacks and hit-test geometry. Plain hover uses the last frame's geometry.
3. `FrameScheduler` coalesces requests and caps frame starts at `maximumRefreshRate` (60 Hz by default). Rendering time counts toward that interval. With no requests or Wayland scroll momentum, it schedules nothing.
4. `FrameProducer` reconciles current blocks, measures/places, registers behavior, then paints those prepared snapshots while tracking observable properties. Painting performs no registration or lifecycle work. A change to a tracked property requests another frame.
5. The backend culls and encodes the draw commands, then submits them to the GPU.

Registration refresh traverses blocks without painting. Custom primitives implement explicit registration and painting phases. Coalescing presentation still does not eliminate reconciliation, measurement, and registration work for each actionable event. Virtualized lists build visible rows, but identified list construction still scans every element's ID; a small command count does not imply cheap construction.

Bodies, callbacks and geometry reconcile conservatively; stable identity alone never establishes validity. Prepared custom children are owned locally through one operation, without paired traversal bookkeeping. The experimental broad geometry cache was removed after measurements showed no end-to-end benefit. Custom blocks implement `PaintableBlock` or `LayoutPreparingBlock`. Identified collections still need explicit revisions or change sets before their ID scans can safely be skipped.

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

Verify which Chroma revision ShapeTree's desktop package resolves before profiling. A remote revision pin does not use the neighboring checkout; deliberately configure a local override for integration and restore the intended dependency before delivery. Build optimized code with symbols, then record the actual app:

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

The scripts copy `Benchmarks/Package.resolved` when present; otherwise they record
`swift package show-dependencies --format json` for the local dependency graph.

Comparisons require matching workloads, configuration, toolchain, dependencies, and hardware. They compare median p50/p95 timings across trials and exit nonzero for regressions above the threshold (default: 15%). Reported spread is not a confidence interval.

## Testing

```sh
swift test --package-path Benchmarks
```
