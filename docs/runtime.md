# Runtime guide

Source baseline: main at `7d9012c3`. Start with the [app quick start](getting-started.md).
The [benchmark guide](../Benchmarks/README.md#how-an-input-reaches-the-screen)
is the canonical input-to-presentation walkthrough and command reference.

## Current contracts

- **Bodies and identity.** [`Block.body`](../Sources/Chroma/Blocks/Block.swift)
  describes current UI without performing actions. [`BlockBuilder`](../Sources/Chroma/Blocks/BlockBuilder.swift)
  gives children structural slots and branches;
  [component types and explicit keys](../Sources/Chroma/Interaction/StructuralPath.swift)
  also contribute to identity. Use stable, unique collection IDs when elements move.
  Identity is not proof that a captured callback or measured size remains current.
- **One operation, one prepared tree.** [`BlockEngine.Resolved`](../Sources/Chroma/Layout/BlockEngine.swift)
  shares prepared children and proposal-keyed measurements within a traversal.
  The next input/registration/frame operation prepares fresh values. Do not retain
  a resolved node or its callback closures as a cross-frame cache.
- **Registration before painting.** Registration installs current interaction behavior
  and geometry. Painting consumes prepared state and appends draw commands; it must not
  register focus leaves, run lifecycle work, or dispatch actions. Registration-only
  refreshes do not paint.
- **Observation ownership.** [`FrameProducer`](../Sources/Chroma/Rendering/FrameProducer.swift)
  tracks observable reads for the current frame. It cancels its previous subscription
  before replacing it; reset and destruction also cancel. Delivery is one-shot and
  generation-checked, so stale callbacks cannot invalidate a replacement frame.
  Subsequent rendering rearms observation. Release hosts when finished, rather than
  keeping prepared trees or subscriptions alive in application caches.
- **Fresh input, coalesced presentation.** [`WindowRuntime`](../Sources/Chroma/Application/WindowRuntime.swift)
  refreshes registrations for actionable input before dispatch. On this baseline,
  plain hover uses the last frame's geometry. [`FrameScheduler`](../Sources/Chroma/Rendering/FrameScheduler.swift)
  coalesces presentation requests, not the work necessary for fresh input callbacks.
  An input burst can require several registration traversals before one paint.
- **Virtualization is not constant-time construction.** Uniform-height lists prepare
  visible rows, but identified collections still validate/compare IDs across their
  input collection. Variable-height rows additionally need measurements to locate
  the visible range. Small draw lists do not prove cheap row construction or ID scans.
  On this baseline, [`ScrollView.Row`](../Sources/Chroma/Blocks/Layout/ScrollView.swift)
  can retain measurements while identity, environment, and observed dependencies stay
  valid. Replacing `content` invalidates them; unobserved captured mutations require
  `invalidateMeasurement()`. These size records are distinct from resolved UI nodes.

## Custom blocks

Use an ordinary `Block` for composition. For lower-level drawing:

- [`PaintableBlock`](../Sources/Chroma/Blocks/PaintableBlock.swift) separates
  `sizeThatFits`, `register`, and `paint`. Choose a `focusRule`: `.control` must
  register a focus leaf, `.standard` permits automatic leaf focus, and `.container`
  or `.decorative` does not add one. [`Button`](../Sources/Chroma/Blocks/Controls/Button.swift)
  demonstrates registration via `buttonState` and painting via `buttonVisualState`.
- [`LayoutPreparingBlock`](../Sources/Chroma/Layout/PreparedLayouts.swift) returns
  one `BlockEngine.Resolved` from `prepareLayout(context:)`. Prepare children with
  `BlockEngine.prepare`, then capture them locally in the returned measurement,
  registration, and painting closures. Forward each phase to the corresponding child
  phase. This contract owns focus explicitly; the engine adds no automatic leaf focus
  to the prepared result. Built-in [layout modifiers](../Sources/Chroma/Layout/PreparedLayouts.swift)
  show the ownership pattern. Do not resolve children again during painting or keep
  prepared children in a controller for reuse by later operations.

Relevant deterministic coverage lives in `StackEvaluationTests`, `WindowRuntimeTests`,
`FrameSchedulerTests`, and the custom-block/paint-isolation tests under
[`Tests/ChromaTests`](../Tests/ChromaTests). Run focused tests with `swift test --filter NAME`,
then the [package checks](getting-started.md#contributor-checks).

## Candidate implementation versus design targets

These are separate from the baseline above:

- Draft [#90](https://github.com/zaneenders/chroma/pull/90), at `5214f532`, includes
  runtime/text code and tests, not just documentation. Its
  [implementation notes](https://github.com/zaneenders/chroma/blob/5214f532effdb9ff795df6a4a7a05577153d35e2/docs/document-selection-implementation.md)
  describe candidate document-owned text-run mapping and offscreen copy. Those APIs
  are not available on this main baseline.
- That branch's [runtime architecture](https://github.com/zaneenders/chroma/blob/5214f532effdb9ff795df6a4a7a05577153d35e2/docs/runtime-architecture.md)
  is **proposal-only**. Window-owned `UIState`, phase-specific capabilities, a unified
  primitive contract, frozen-graph serial walkers, revision-keyed identity indexes,
  and required-row-only variable-height expansion are design targets, not shipped APIs.
- Main's [document selection](../Sources/Chroma/Interaction/DocumentSelection.swift)
  still derives order from registered focus leaves. Track virtualization/selection in
  [#87](https://github.com/zaneenders/chroma/issues/87), identity work in
  [#93](https://github.com/zaneenders/chroma/issues/93), and registration work in
  [#103](https://github.com/zaneenders/chroma/issues/103).
  [Scroll ownership #85](https://github.com/zaneenders/chroma/issues/85) remains separate.
