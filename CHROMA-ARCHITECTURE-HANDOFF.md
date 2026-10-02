# Chroma architecture handoff

Prepared on 2026-10-02. Repository state and measurements below describe the handoff baseline; verify them before starting work.

Work on Chroma’s rendering and interaction architecture, using ShapeTree as the integration application. Implement and validate the redesign; don’t stop at recommendations.

The central requirement is to **make cache validity explicit while preserving fresh callbacks and correct input ordering**.

The immediate scrolling regression has already been substantially fixed. The user reported **“Smooth now”** after the latest sidebar virtualization. Your task is to remove the remaining architectural coupling between layout, input registration, and painting without losing those improvements.

## 1. Start from the published fixes

| Repository | Directory | Branch | Published commit |
|---|---|---|---|
| Chroma | `/Users/zane/Developer/chroma` | `clean-up` | `6242fe87161138c7e1ff65cfe6a75a6dc784e651` |
| ShapeTree | `/Users/zane/Developer/shape-tree` | `feat/shapetree-owned-scribe-ui` | `3654aca0c0940e55756d5bb242e75d18de2d1241` |

Both working trees were clean when the handoff baseline was checked, before this document was added. Recheck their state and repository instructions before editing.

ShapeTree’s desktop package is at `/Users/zane/Developer/shape-tree/apps/shape-tree-desktop`. Its `Package.swift` and `Package.resolved` currently use the **remote Chroma revision above**.

This matters: editing the neighboring Chroma checkout will not automatically change ShapeTree. For local integration, deliberately switch the desktop package to the neighboring checkout or establish another verified local override. Confirm which Chroma sources the build actually uses. Before delivery, restore the intended dependency configuration; if publication is requested, push Chroma first, then pin ShapeTree to the published hash.

ShapeTree’s [AGENTS.md](../shape-tree/AGENTS.md) prohibits **all `@unchecked` uses, including `@unchecked Sendable`**. Resolve isolation and ownership correctly.

The user is comfortable replacing poor internals. Preserve working application behavior and meaningful regression coverage.

## 2. Understand the current pipeline before designing its replacement

Read these files first:

| Area | Starting point |
|---|---|
| Input ordering and presentation scheduling | [WindowRuntime.swift](Sources/Chroma/Application/WindowRuntime.swift) |
| Registration refresh and observation lifetime | [FrameProducer.swift](Sources/Chroma/Rendering/FrameProducer.swift) |
| Resolution and measurement caching | [BlockEngine.swift](Sources/Chroma/Layout/BlockEngine.swift) |
| Prepared built-in layouts | [PreparedLayouts.swift](Sources/Chroma/Layout/PreparedLayouts.swift) |
| Primitive extension boundary | [PrimitiveBlock.swift](Sources/Chroma/Blocks/PrimitiveBlock.swift) |
| Stateful controls | [Interactive.swift](Sources/Chroma/Blocks/Controls/Interactive.swift), [TextEditor.swift](Sources/Chroma/Blocks/Controls/TextEditor.swift) |
| Interaction and focus | [Interaction.swift](Sources/Chroma/Interaction/Interaction.swift), [NavigationInteraction.swift](Sources/Chroma/Interaction/NavigationInteraction.swift) |
| Scrolling and virtualization | [ScrollView.swift](Sources/Chroma/Blocks/Layout/ScrollView.swift), [ScrollViewController.swift](Sources/Chroma/Interaction/ScrollViewController.swift) |

The simplified pipeline is:

```text
Block values and bodies
    → resolved children
    → measurement and placement
    → drawing traversal, which also registers interaction
    → DrawList
    → renderer
```

The remaining problem is visible in `FrameProducer.refreshRegistrations`:

```swift
var discarded = DrawList()
BlockEngine.draw(content, into: &discarded, ...)
```

Before actionable input, Chroma traverses and draws the UI to refresh hit regions, focus structure, handlers, callbacks, and text-related state. It then discards the drawing commands.

Presentation performs another traversal to produce the real drawing commands. Passive hover already avoids refreshing registrations for every pointer event.

**Removing the discarded array alone does not solve this.** A sink that ignores drawing commands still executes the drawing traversal and its associated work. The goal is to separate the responsibilities that currently require that traversal.

## 3. Preserve the improvements already shipped

The current implementation already addresses several distinct problems:

- `BlockEngine.Resolved` caches measurements by proposal and lazily computes expansion properties **within one traversal**.
- Built-in containers and modifiers share prepared child trees between layout queries and drawing.
- Ordinary `ScrollView` shares resolved content between measurement and drawing within its traversal.
- `Interactive` shares its idle content for measurement, then resolves the current interaction phase for drawing.
- Passive hover reuses the last interaction geometry until presentation.
- Frame pacing measures the interval from frame start, so render time is included in the frame budget.
- ShapeTree’s session sidebar constructs expensive controls only for visible rows.
- A focus-recovery bug that moved the viewport before the next click has been fixed.

Do not describe the current prepared tree as a persistent retained tree. It expires after the operation. Its measurement cache is deliberately safe because it does not survive arbitrary changes between operations.

Do not make `Interactive` paint its cached idle content. Hovered and pressed content can differ, including structurally.

Do not assume virtualization makes every operation proportional to visible rows. Uniform-row identity handling still scans the collection’s IDs, and ShapeTree still assembles lightweight row metadata. Those are separate potential optimizations.

Do not increase refresh frequency or introduce continuous rendering to conceal expensive work. Preserve the ability to return to idle.

## 4. Treat input freshness as a hard correctness contract

Input events are processed in order. Presentation can coalesce; actions cannot disappear, replay, or use stale state.

A particularly important existing test constructs this button:

```swift
DeferredBlock {
    let count = model.actions
    return Button("Increment") {
        model.actions = count + 1
    }
}
```

Two activations before the next presentation must produce `2`. Retaining the first closure would produce `1`.

Likewise, inserting a newline and then moving the caret up before the next presentation must use the updated text layout.

These examples explain why registration refresh currently exists. You must replace the mechanism while preserving its guarantees.

Enforce the following:

- Each input event is applied exactly once and in order.
- Before an event needs a callback or geometry, that information must reflect relevant preceding changes.
- A press followed by a rebuilt control’s release uses the current action, subject to identity and cancellation rules.
- Removing or replacing the pressed control cancels the old interaction.
- Events arriving before the initial frame still work.
- Presentation never replays input edges or application actions.
- Geometry, clipping, focus structure, and hit regions used together must belong to a consistent update.

**Stable identity does not prove unchanged content.** The same ID can have a different callback, label, text layout, child structure, or theme.

Arbitrary closures can capture mutable values that Swift Observation does not track. You cannot transparently retain all such closures indefinitely. Choose and document a sound contract: observable dependencies, explicit invalidation/revisions, conservative reconciliation, or an explicit combination. Maintain conservative behavior wherever validity cannot be established.

## 5. Give each phase a clear responsibility

Design the replacement around responsibilities like these; the exact type names are yours to choose:

| Responsibility | What it owns |
|---|---|
| Reconciliation | Current block values, child structure, identity, configuration, and current behavior |
| Measurement | Intrinsic sizes and proposal-dependent results |
| Placement | Rectangles, transforms, clipping, and visible ranges |
| Interaction registration | Current actions, command scopes, focus relationships, text-editing information, and hit regions |
| Input dispatch | Applying an event once against current interaction state |
| Painting | Producing drawing commands from current visual state and valid geometry |

Measurement must not dispatch application actions, consume focus requests, or depend on how often it is called.

Painting should eventually stop being the mechanism that discovers or refreshes input handlers. Move lifecycle and application-state effects currently hidden in drawing into explicit update or input phases.

Text shaping may be needed by both layout and editing. Give shared text-layout results a clear owner and validity rules; moving duplicate work between phases is not an improvement.

Begin with a complete path through the system that supports real controls and a virtualized list. Avoid building a large retained framework before proving its behavior in the actual runtime.

## 6. Separate registration from painting before introducing broad retention

Use this implementation sequence:

1. Establish reproducible counters and benchmarks for the current code.
2. Introduce a genuine registration/update path that does not require painting migrated controls.
3. Migrate enough built-in containers, modifiers, controls, and scrolling behavior to exercise that path in ShapeTree.
4. Verify input semantics with the existing tests and targeted new regressions.
5. Add persistent layout reuse only after defining its invalidation and lifetime rules.
6. Migrate remaining relevant application primitives and remove superseded paths.

During the first stage, rebuilding some bodies conservatively is acceptable. Calling the normal paint traversal and throwing away its output is not the intended result.

A temporary compatibility path for custom `PrimitiveBlock` implementations may be necessary. Make it explicit, count its use, and identify the remaining callers. Do not claim registration is paint-free throughout ShapeTree if its custom wrappers still force the legacy path.

Prefer a small, integrated change with measurable benefits over a second engine that sits beside the original indefinitely.

## 7. Define invalidation before keeping anything across frames

For every retained object, answer:

- What makes it valid?
- What invalidates it?
- Who observes that change?
- Which parents or descendants become dirty?
- When is it refreshed?
- When is it released?

Distinguish at least these kinds of change:

| Change | Likely consequences |
|---|---|
| Callback or command-handler replacement | Refresh behavior; geometry may remain valid |
| Text, font metrics, constraints, or child structure | Reconcile and invalidate affected measurement/placement |
| Scroll offset | Update visible content, transforms, clipping, and hit regions; some measurements may remain valid |
| Pure visual change | Repaint where layout is demonstrably unaffected |
| Viewport resize | Recompute dependent proposals and placement |
| Root replacement or identity removal | Dispose obsolete retained state and cancel affected interactions |
| Theme/environment change | Invalidate all dependent results, including geometry when metrics change |

This table is a starting model, not proof that a particular change is always local. For example, interaction-phase content can change size, so hover cannot universally be classified as paint-only.

A changed child can alter its parent’s size and reposition siblings. Propagate invalidation through actual layout dependencies.

Observation needs particular care:

- Current frame observation is one-shot and uses cancellation and generation checks.
- Per-node observation needs equivalent rearming and disposal.
- Delayed callbacks from an old root must not dirty or resurrect its replacement.
- Unchanged frames must not accumulate subscriptions.
- Removing nodes must release subscriptions and captured state.
- A queued observation notification is not proof that the next input event has current geometry.

Keep UI-owned state correctly isolated on the main actor. Handle cross-actor notification delivery with checked language constructs.

Bound caches and their lifetimes. Do not retain every node, measurement proposal, or offscreen row ever encountered.

## 8. Audit ShapeTree’s custom primitives as part of the design

The real application has wrappers that rely on today’s traversal semantics. Inspect the desktop sources under `apps/shape-tree-desktop/Sources/ShapeTreeDesktop`, especially:

- `ScribeSourceContent.swift`
- `ScribeUI/ScribeRenderContext.swift`
- `ScribeUI/ScribeWorkspaceScope.swift`
- `ScribeUI/TranscriptView.swift`
- `ScribeUI/ComposerBar.swift`
- `ScribeUI/RenameSessionDialog.swift`
- `ScribeUI/SessionBrowser.swift`

Known boundaries include `ScribeSourceCommands`, `BlockContextBridge`, `TranscriptViewport`, `WorkspaceNavigation`, `NavigableTranscriptItem`, and `CommandRevealTranscript`.

Some establish ambient context during measurement or drawing. Others update viewport information, install command handling, or handle focus/editing transitions during traversal.

A retained child must not accidentally keep the context from an earlier traversal. Move these dependencies into explicit ownership and update boundaries, or preserve their behavior through a documented adapter until migrated.

Keep the existing sidebar virtualization. It currently flattens lightweight keyed rows into a uniform-height virtualized list, with rows at 30 points and spacing of 1 point. Do not restore an outer ordinary scroll view or eagerly construct every row’s controls.

## 9. Use the regression suite as a specification

Read the tests before changing behavior. In particular:

- `WindowRuntimeTests`: ordered input, current callbacks between coalesced activations, updated text layout between editing events, initial-frame input, hover reuse, and idle behavior.
- `RegistrationRefreshTests`: registration refresh must not replay clicks, text, pointer edges, or scrolling.
- `StackEvaluationTests`: sharing within a traversal, fresh evaluation between operations, proposal-sensitive measurements, and current-phase interactive drawing.
- `StructuralInteractionTests`: keyed reordering, identity changes, current release actions, removal/reinsertion cancellation, focus binding, background actions, and virtualized press cancellation.
- `PointerScrollFocusTests`: focus recovery after virtualization must not move the next click target.
- `ObservationLifetimeTests` and `ObservationDeliveryTests`: subscription cleanup and stale-notification handling.
- `FramePacingTests`: rendering time belongs inside the frame interval.

One regression deserves explicit preservation: after scrolling a virtualized list, recovering keyboard focus must not reveal a partially visible row and shift the viewport underneath the next pointer click.

Add meaningful tests for the new architecture:

- Registration of migrated controls performs no painting.
- Updating a callback with unchanged geometry invokes the new callback.
- Known unchanged geometry avoids repeated measurement.
- Changing a leaf’s intrinsic size updates dependent parent and sibling layout.
- Scrolling updates hit regions and clipping correctly.
- Changing variable-height row content invalidates its measurement.
- Root replacement rejects already queued invalidations.
- Removed retained nodes release their observation and interaction state.
- A change followed immediately by input works before asynchronous observation delivery runs.

Do not weaken freshness tests merely to make a cache pass. If an API contract deliberately changes, explain the change, migrate callers, and retain coverage of the user-visible behavior.

## 10. Measure pipeline work and application behavior separately

Record at least:

- Body evaluations.
- Measurement calls and cache hits.
- Placement work.
- Registration work.
- Paint calls and emitted drawing commands.
- Compatibility-path invocations.
- Live retained nodes and observation subscriptions.

Use counters that can be disabled or compiled out. Avoid expensive logging inside benchmarked paths.

Existing evidence provides context:

| Workload | Previous measurement |
|---|---|
| Synthetic nested layout, depth 5, scroll case | p50 improved from approximately 129.695 ms to 0.835 ms |
| Same synthetic case, body evaluations | 12,600 to 40 per frame |
| Interactive nested fixture, depth 5, scroll case | p50 improved from approximately 6.238 ms to 3.377 ms |

The interactive fixture’s baseline already included an earlier optimization. These numbers do not share one universal baseline and are not whole-application speedups.

Manual application profiles had different amounts of active interaction. Do not turn their total sampled CPU times into before/after speedup ratios. Inclusive stack samples overlap and cannot be added together.

The latest local application profile is under:

`/Users/zane/Developer/chroma/Benchmarks/results/shape-tree-virtualized-profile/`

These benchmark results and traces are ignored local artifacts; another checkout may not contain them.

Create comparable release measurements using the same dataset, viewport, interaction sequence, build configuration, warmup, and sampling method. Separate first-frame cost, active interaction cost, and idle behavior. Preserve matching binaries and debug symbols when comparing traces.

Use the existing commands as starting points:

```bash
cd /Users/zane/Developer/chroma

swift test
swift test --package-path Benchmarks

swift run --package-path Benchmarks -c release LayoutBenchmark
swift run --package-path Benchmarks -c release LayoutBenchmark --interactive
swift run --package-path Benchmarks -c release InputFrameBenchmark
```

After deliberately configuring and resolving ShapeTree’s dependency to the intended Chroma version:

```bash
cd /Users/zane/Developer/shape-tree/apps/shape-tree-desktop

swift test --disable-automatic-resolution

swift build -c release -Xswiftc -g \
  --disable-automatic-resolution \
  --product ShapeTreeDesktop
```

Do not benchmark while competing builds run.

Previously validated totals were 396 Chroma tests, 154 ShapeTree desktop tests, and 3 benchmark-package tests. Treat those as historical checks, not a substitute for running the updated code.

Profile the actual newly built executable. Do not launch an installed app and assume it contains your changes. Attach Instruments’ Time Profiler to a verified process, or launch the desktop executable through `xctrace`. An attached recording is useful when the application should remain open afterward.

The [benchmark README](Benchmarks/README.md) contains profiling guidance, but its statement that ShapeTree uses the neighboring Chroma checkout became stale when the remote revision was pinned. Verify the package configuration directly.

## 11. Finish with concrete acceptance evidence

The work is successful when:

- The migrated registration path does not call painting to discover input behavior.
- Current callbacks and input-dependent layouts remain correct between presentations.
- Retained geometry has explicit, tested validity rules.
- Changes update the required layout dependencies without unnecessary whole-tree work where validity permits reuse.
- ShapeTree remains smooth during scrolling, session switching, typing, and navigation.
- Idle windows return to idle.
- Removed nodes and replaced roots release retained resources.
- Core changes remain compatible with Chroma’s macOS/Metal and Linux/Wayland boundaries.

Do not introduce platform-specific profiling dependencies unconditionally into the core library.

Deliver the implementation, tests, and a concise explanation of the resulting data flow. Include a before/after table with reproducible workload descriptions, counts, and timing distributions. Identify remaining compatibility fallbacks, API migration requirements, and any unmeasured claims.

Keep publication separate from implementation unless the user requests it. If asked to commit and push both repositories, publish Chroma first and pin ShapeTree to that exact remote commit.

The first concrete milestone should be **fresh, ordered input handling through a registration path that does not paint**. Persistent subtree reuse should build on that verified separation and an explicit invalidation contract.
