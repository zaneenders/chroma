# Chroma Benchmarks

Run commands from the repository root. Use release builds and consistent hardware, toolchain, and workloads when comparing results.

On systems without native display libraries, set `CHROMA_HEADLESS_ONLY=1` to omit
the native render runner while retaining CPU benchmarks and fixture tests:

```sh
CHROMA_HEADLESS_ONLY=1 swift run --package-path Benchmarks -c release LayoutBenchmark
CHROMA_HEADLESS_ONLY=1 swift run --package-path Benchmarks -c release InputBacklogBenchmark \
  --workload stress --rows 1000 --depth 3 --events 60 --trials 3
```

These headless results measure CPU/runtime work, not backend or display performance.

See [the runtime redesign measurements](RUNTIME_RESULTS.md) for one bounded baseline comparison and its limitations.

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
that observation subscriptions are released; buffer capture lifetime is covered by tests.

This intentionally stresses whole-collection ID scans as well as visible layout:
virtualization does not eliminate metadata scanning. Timings exclude native event
loops, GPU work, and refresh deadlines. `run.sh` includes `stress-headless.json`
in every collection; `CompareBenchmarks` checks its workload, viewport, schema/fixture
versions, warmup and sample counts before comparing each phase’s p50/p95.
The single-sample first-frame phase is also compared, but is noisier than steady state.
Use the native example for manual profiling, not as evidence of frame-rate guarantees.

`PipelineMetrics.isEnabled = true` starts an opt-in capture. `PipelineMetrics.reset()` clears work counters and resets peaks without hiding currently live objects; `PipelineMetrics.snapshot` reads results. Disabling avoids recording and lifetime-token allocations. Prepared payloads and their proposal caches remain **operation-scoped** in reused buffers. `layoutNodes` counts records and `bufferGrowths` counts storage capacity changes, not mallocs. No cross-frame subtree geometry cache is retained. `drawingCommands` counts engine/frame entry points, not unrelated direct `DrawList` construction, and `measurements` includes cache hits. `placements` counts resolved-node visits with an assigned rectangle rather than distinct constraint-solver operations. Run release timings only when other builds, tests, and profiling processes are idle.

## Input frames

```sh
swift run --package-path Benchmarks -c release InputFrameBenchmark
```

Measures the headless rendering path through `ChromaTesting.HeadlessHost` for scrolling lists with 1,000, 100,000, and 1,000,000 items, with and without explicit identity. Prints one cold and five warm frame timings per case:

- `replace-root` constructs and replaces the root before every render. `setup` includes construction and replacement; `render` includes registration and drawing. Even warm iterations reset the interaction tree.
- `deferred-root` keeps a `DeferredBlock` installed, as an app does, and constructs its list during traversal. Warm iterations keep the interaction tree. List construction is included in `render` and can occur more than once per input frame.

These timings exclude native input dispatch, scheduler waits, Metal encoding, and GPU execution. They are not consumed by `CompareBenchmarks`.

## Sustained input backlog investigation

See [the deterministic backlog experiment](INPUT_BACKLOG.md) for runtime recovery
regressions and a configurable queueing model. It separates CPU saturation,
completed dispatch opportunities and compositor readiness without claiming native
latency measurements or changing input scheduling. The same guide documents
`InputBacklogBenchmark`, a real-runtime scheduled headless replay with an
independent ordered source, measured input cost, draw-completion coverage and idle
recovery. Its measurements are separate from the deterministic model and native
Wayland/physical-display validation.

## Multiline text selection

```sh
swift run --package-path Benchmarks -c release TextSelectionBenchmark
```

Replays keyboard Select All on 10, 50, and 100 explicit lines of 80 characters in
an 800×600 `HeadlessHost`. Reports unselected and selected command counts separately
from selected-render p50/p95 milliseconds (5 warmups, 20 samples, lower median and
nearest-rank p95). Selection input is applied before timing. Run on idle hardware;
these samples exclude native dispatch, backend encoding, and GPU execution and do
not establish native FPS. The command-count regression is deterministic and lives
in `TextSelectionPaintingTests`, alongside partial-range, wrap, Unicode, document
selection, caret, and paint-isolation coverage.

## Markdown preparation

```sh
swift run --package-path Benchmarks -c release MarkdownBenchmark
swift test --filter 'Markdown|PreparedMarkdownLayoutTests'
```

The fixed fixtures cover 200 static paragraphs, the same document with a changing
incomplete streaming tail, a three-column viewport, and an 8,000-character unbroken
fenced-code line. Each case uses five warmups and 30 measured frames, a 600-point
viewport height, the lower median, and nearest-rank p95. Static/narrow/code cases
retain their root; streaming replaces the root for each appended tail and includes
that setup in its timing. Reports include source bytes, command counts and a separate
instrumented replay of the last sample. Work counters are disabled during timing.
The timing fixture uses atlas-supported glyphs to avoid synchronous missing-glyph
logging (#99); Unicode graphemes remain covered by the correctness tests.

These are headless full-frame CPU timings: document parsing, layout, interaction
registration and command generation are included together. They are not parser-only
timings, native rendering, GPU measurements, or frame-rate guarantees. Run matched
builds serially on an idle machine; no wall-clock threshold is used in tests.
Operation-local tests separately verify one leaf preparation for matching measurement,
registration and painting, input invalidation, relocated geometry, and callback lifetime.
The parsed document and offscreen traversal are still rebuilt for each operation.

See [the recorded comparison](MarkdownPreparationResults.md) for the initial matched results.

## Nested layout

```sh
swift run --package-path Benchmarks -c release LayoutBenchmark
swift run --package-path Benchmarks -c release LayoutBenchmark --interactive
```

Measures 20 session-style rows in a scroll view under one, three, or five layers of groups and stacks. Each case warms up for three frames and reports 20 frames as JSON: p50/p95 time, row emissions per frame, and draw-command count. The existing `bodiesPerFrame` field now counts calls to the row emitter, preserving the report schema and the same row-content construction point previously counted through a body getter. `none` explicitly renders without input; it does not measure application idle CPU. `scroll` includes input registration and the resulting frame. These reports are not consumed by `CompareBenchmarks`.

`--interactive` wraps each layer in a control. Within an update, each requested phase is emitted once with the control's child focus context. Idle measurement and idle registration use the same nodes; a distinct current phase has its own nodes. Painting consumes the registered phase without emitting more content.

Increasing container depth must not multiply row emissions. A single `LayoutBuffer` owns typed nodes and shares children across expansion checks, measurement, registration, and drawing. Node measurements are memoized by proposal for that operation only. A new update emits current state and reinstalls observation tracking. Built-in controls use typed payloads; external leaves can supply their own measure, register, and paint operations through `customLeaf`.

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

Content, callbacks, and geometry are rebuilt for each operation; stable identity alone never establishes validity. Custom blocks implement the optional `Block.emit(into:context:)` authoring method and use the same typed buffer constructors as direct construction. There is no separate primitive or preparation protocol. Identified collections can opt into bounded identity-index reuse with an explicit `identityRevision`; current row values and actions are still rebuilt.

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

On Linux, replay the same fixtures through the real GLES driver with a surfaceless EGL pbuffer:

```sh
swift run --package-path Benchmarks -c release RenderBenchmark --scene scrolling --stage opengl
swift test --filter OpenGLRenderingTests
```

The replay/tests require Mesa surfaceless EGL with an ES3 pbuffer configuration; no Wayland window is opened.
For CI without a GPU, a Mesa software driver can run the pixel tests; never compare its performance to hardware rendering.
Reports include the GL vendor/renderer/version, and the final frame's instance count, draw calls,
instance-buffer payload upload calls and bytes. Upload counters exclude texture uploads and buffer orphaning.
`openGLEncode` measures frame clear, renderer culling/preparation, uploads and draw submission.
`openGLCompletion` measures the following `glFinish` CPU wait, **not GPU execution time**; work may overlap
encoding or block inside driver calls. Neither phase includes Wayland input, layout, swap/compositor scheduling,
or display latency. Use the native `StressExample` for separate interactive scrolling profiling.

Adjacent quads batch only when resource identity and effective clip agree. Instances remain ordered,
including translucent overlaps; image generation/dimension changes flush before texture replacement.
CPU staging is capped at 4,096 instances (~544 KiB), and each bounded GPU store is orphaned before reuse
so outstanding draws keep their original data. `OpenGLRenderer` requires a current ES3 context on the
calling thread for setup, encoding and cleanup; do not suspend or move threads while relying on that context.

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

Collect all scenes, or select scenes with `SCENES`. Set `METAL=1` on macOS to include Metal measurements,
or `OPENGL=1` on Linux to include surfaceless EGL/GLES replays (driver metadata must match for comparisons).

```sh
Benchmarks/Scripts/run.sh Benchmarks/results
SCENES="scrolling selection" METAL=1 Benchmarks/Scripts/run.sh Benchmarks/metal-results
SCENES="scrolling text" OPENGL=1 sh Benchmarks/Scripts/run.sh Benchmarks/opengl-results

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
