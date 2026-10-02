# Explicit update, input, geometry, and painting

Chroma uses one block engine. Fresh behavior is reconciled before actionable input;
painting consumes that update's prepared children, geometry, and text snapshots.
An opt-in bounded cache retains geometry across updates, never blocks or callbacks.

## Data flow and ownership

1. Before each actionable event, `WindowRuntime` refreshes a consistent registration
   snapshot: current blocks, measurement/placement, clipping, focus/command scopes,
   scroll regions, text layouts, and callbacks. Passive hover keeps its existing
   last-frame reuse policy.
2. Native raw keys refresh registration **before** resolving scoped bindings and
   editing mode, then dispatch within the same update scope. Keyboard refresh uses
   one clipped buffer row in each direction so navigation needs no second traversal.
   Wayland stamps the resulting text event with the refreshed editing-session ID.
   Raw keys and already-resolved events queued before the initial frame retain their
   mixed ordering. Standalone resolution stays conservative; no freshness promise
   survives arbitrary changes between separate API calls.
3. Input is applied once in order. Registered raw-input observers run after core
   handlers/actions and before release/drag cleanup. They never run for neutral
   presentation. Pre-initial-frame events remain queued in their original order.
4. Presentation reconciles a fresh update under Observation, calls registration,
   then pure painting, then publishes the completed interaction frame and draws
   navigation decoration. Presentation carries no replayed event edges/actions.
5. `PaintableBlock.paint` emits drawing commands. It does not install handlers,
   consume focus/scroll requests, mutate application state, or advance drag state.
   Those effects belong to explicit registration/update or input callbacks.

`Resolved` body values and its proposal memoization still last only for one
operation. Containers share their placement arithmetic and operation-local child
rectangles between update and paint. `Interactive` measures idle content but
registers and paints the actual current-phase child snapshot, including structural
differences. It never paints the cached idle tree merely because identity is stable.

Opaque custom wrappers use paired `BlockEngine.register` / `BlockEngine.paintRegistered`
calls in the same child order. `PreparedPaintScope` carries those newly prepared
children only through the corresponding operation. The runtime clears it explicitly
at the end, breaking context/child closure cycles. It is not a retained UI tree.

Text measurement, input hit testing/caret motion, and painting share immutable
`TextLayoutSnapshot` values. A one-entry operation-local preparation cache checks
exact text and column count; metrics, rectangle, padding, and editor configuration
form the current placement snapshot. A later update rebuilds snapshots from fresh
values. Pure painting neither rereads the editor binding nor reshapes committed text.

## Opt-in retained geometry

Keep a `LayoutCache` token stable and wrap a subtree in `CachedLayout(cache) { ... }`.
Its builder and all behavior are evaluated fresh each update. The window retains
only sizes by proposal and relative stack-child rectangles.

The contract is explicit:

- Read observable layout dependencies **inside** the content builder or measurement.
  Their notifications synchronously invalidate the boundary, before queued redraw
  delivery. An immediate following input therefore cannot use already-invalid sizes.
- Call `cache.invalidate()` when geometry depends on unobserved mutable values,
  closures, or ambient state. Observation cannot make arbitrary captured values safe.
- Callback-only changes do not require invalidation when geometry is unchanged.
  Callbacks always reconcile, including the captured-count two-activation case.
- Type/structural-path and layout-environment signatures validate each fresh tree;
  proposals key measurements. Changed text, metrics, theme, constraints, or structure
  cannot inherit unrelated geometry. Nested boundaries share their outer boundary's
  invalidation scope and token signature rather than creating a dependency graph.
- Dirty geometry invalidates that explicit boundary. Uncached parents recompute
  dependent size and sibling placement; independent unchanged boundaries can reuse
  geometry. This is deliberately coarse and predictable, not arbitrary leaf-local
  retained rendering.
- Dynamic children discovered after a boundary's reconciliation are conservative.
  For example, ordinary scrolling's dynamically resolved content is not implicitly
  retained by an outer boundary. Place an explicit boundary where dependencies are
  known; no automatic cross-frame reuse is inferred from a stable ID.

| Retained state | Owner / validity | Release |
|---|---|---|
| Cached boundary sizes and relative placements | Window store; current token, fresh structure/environment signature, valid observed dependencies or explicit revision | Swept when absent from a complete update, root reset, or owning runtime destruction |
| Variable-row measurements | Existing `ScrollViewController`; row measurement identity, width/path/environment, observed dependencies | Row replacement/removal from cache or controller disposal |
| Current handlers, focus, copy/select-all providers and text snapshots | Current consistent interaction registration | Next registration, root reset, or owning runtime destruction |
| Frame observation | Current producer generation, one-shot subscription | Rearmed/cancelled per frame/reset; stale queued delivery rejected |

Persistent geometry is bounded to 64 boundaries per window, 256 nodes per boundary,
and 4 measurement plus 4 placement proposals per node. Overflow falls back to
conservative computation. Proposal eviction conservatively invalidates the whole
boundary; its next reconciliation clears/rearms dependencies. This avoids complex
subscription-dependency machinery. Unchanged frames do not accumulate subscriptions.
UI-owned state stays on the main actor; notification validity uses checked
`Synchronization.Mutex`, without `@unchecked`.

Variable rows also expose `row.invalidateMeasurement()` for unobserved geometry
changes. Assigning `row.content` invalidates automatically. Keeping a controller
alive intentionally keeps its current row cache; no claim is made that external
controller-owned state disappears before its owner releases it.

## Compatibility and migration

Existing `PrimitiveBlock.draw` remains a source-compatible combined operation.
A primitive adopts `PaintableBlock` to promise pure presentation, implements
`register` for current behavior/geometry, and implements `paint` for commands.
Use `BlockContext.registerFocusable` without drawing a focus highlight, and
`registerInputHandler` for raw event behavior. A custom wrapper must preserve child
visitation order between registration and painting. These engine calls operate
inside a Host update, not as standalone frame builders.

For unmigrated custom primitives, the explicit adapter remains measurable:

- Before input, the default registration adapter calls legacy `draw` into a discarded
  list, preserving old custom behavior conservatively.
- During presentation update, legacy drawing runs once and its commands are captured.
  The painting phase appends those commands without replaying actions or registration.

This fallback is intentionally not called paint-free. `PipelineMetrics` names its
concrete callers. All built-ins use separated registration/painting; the companion
ShapeTree patch migrates all twelve application primitives, including TranscriptView's
former body-time lifecycle effects. Legacy public entry points remain for external
callers; the runtime's migrated path does not invoke their combined traversal.

ShapeTree's ambient render/workspace context is re-established for every update and
paint. Selection, viewport and command registration, focus reconciliation, and drag
continuation live in update; Escape/modal/press/release effects live in ordered input.
The sidebar retains its 30-point uniform rows with 1-point spacing and constructs
expensive controls only for visible rows. Uniform identity and lightweight metadata
still scan the full collection; no O(visible rows) claim is made for those operations.

## Evidence

Opt-in `PipelineMetrics` reports bodies, measurements/hits, retained placement hits,
registration, painting, commands, text layouts, named fallbacks, and live/peak node
and subscription counts. Timing and counter capture are separate. Disabled captures
avoid logging and lifetime-token allocation. Counters distinguish transient prepared
nodes from retained geometry; cached closures are not an optimization strategy.

See [the acceptance checklist](ArchitectureHandoffChecklist.md) and
[measured results](RegistrationResults.md). Tests cover ordered input, fresh callbacks,
text-layout freshness, phase structure, measurement purity, cache invalidation and
parent/sibling propagation, clipping/scroll/focus recovery, stale delivery, resource
release, legacy adaptation, and idle scheduling. Native graphics validation is
separate from these headless block-graph checks.
