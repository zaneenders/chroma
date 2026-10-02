# Explicit update, input, and painting

Chroma uses one block engine. Fresh behavior and geometry reconcile before actionable
input; painting consumes that operation's prepared values. Internal phases are
explicit while a custom control can declare its work together in one local method.

## Data flow

1. `WindowRuntime` prepares a consistent registration snapshot before each actionable
   event: current blocks, measurements/placement, clips, focus/command scopes, scroll
   regions, text layouts and callbacks. Passive hover reuses last-frame geometry.
2. Native raw keys refresh registration **before** resolving scoped bindings and
   editing mode, then dispatch against that same update. Wayland stamps text events
   with the refreshed editing session. Mixed raw/resolved events queued before the
   first frame preserve their order, including reentrant root replacement.
3. Input is applied exactly once. Registered input observers run after core handlers
   and before drag-release cleanup. Presentation does not replay them.
4. Presentation reconciles a fresh tree under Observation, registers its behavior,
   then paints its prepared values and publishes the completed interaction frame.
   Measurement and painting never dispatch application actions or consume focus
   requests; lifecycle work belongs to explicit update or input callbacks.

Bodies, callbacks and ordinary geometry caches live for **one operation**. Containers
share prepared children, proposal results and relative placements within that
operation. `Interactive` measures idle content but updates and paints the actual
current-phase child, even when its structure differs. No continuous rendering is
needed; the existing scheduler, observation generation checks and idle behavior stay.

## Locally owned custom children

A paint-only leaf implements `PaintableBlock`: `register` installs current behavior,
and `paint` emits commands. A custom wrapper can instead implement the existing
`LayoutPreparingBlock` extension point, now public:

```swift
struct Wrapper<Content: Block>: LayoutPreparingBlock {
  let content: Content
  let onInput: @MainActor (InputState) -> Void
  var focusRule: FocusRule { .container }

  @MainActor
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    let child = BlockEngine.prepare(content, context: context)
    return BlockEngine.Resolved(
      child: child,
      register: { rect in
        context.registerInputHandler(onInput)
        child.register(in: rect)
      },
      paint: { list, rect in child.paint(into: &list, in: rect) })
  }
}
```

One local prepared object owns the child and its callbacks through measurement,
registration and painting. There is no global child queue, matching traversal index,
or requirement that paint visit siblings in registration order. A wrapper can keep
children in ordinary local variables and choose the correct compositing order.
Default primitive measurement/registration/drawing entry points avoid repeating
these forwarding methods. The optional combined `draw` closure supports old entry
points; runtime presentation uses separated registration and painting.

`LayoutPreparingBlock` is a low-level composition boundary: its prepared result owns
all focus registration and highlights. The engine does not add the generic
`PrimitiveBlock.focusRule` fallback around it. Wrappers normally forward focus to
their prepared children; a custom prepared focus leaf must explicitly use
`context.registerFocusable` and `context.paintFocusHighlight` in the respective
phases. Prefer `PaintableBlock` for ordinary leaves, which retain the engine's
automatic focus handling. Give independent children distinct `context.childScope`
values so their identities remain independent even when paint order differs.

Do not retain a `Resolved` object across operations. Do not do application lifecycle
work in `prepareLayout` or measurement. If an update must change state before building
a child, construct that child inside `register`, retain it in the operation's local
closure state, then paint that exact child. Ambient application context must be scoped
and restored around the phases that use it. A paint follows registration on the same
prepared object; it does not reread bindings or construct a second child tree.

## State and cache ownership

Stable identity answers **which control**; it does not establish unchanged callbacks,
content or geometry. Durable selection, expansion and application data retain their
application-owned identities when a row goes offscreen. Transient UI construction
and cache residency do not own those lifetimes.

The experimental `CachedLayout`/`LayoutCache` and its cross-frame geometry subscriptions
were removed after review of Ryan Fleury's UI series and our measurements. They
eliminated a few measurement computations without reducing bodies, metadata scans or
end-to-end latency. This supersedes the handoff's broad retained-layout milestone;
we do not claim persistent subtree geometry reuse. Rebuild the visible graph cheaply
before introducing another validity mechanism.

Useful specialized caches remain:

- Resolved proposal results and prepared placements: owned by one operation.
- Immutable text snapshots: exact text/column validity, shared by measurement,
  editing and painting in that operation.
- Variable-row measurements: existing controller-owned row cache with observed
  dependencies, environment/proposal validity and explicit `row.invalidateMeasurement()`
  for unobserved geometry changes. Assigning `row.content` invalidates automatically.
- Frame observation: one-shot, rearmed/cancelled with generation checks; removed roots
  cannot be revived by delayed notifications. Current registration callbacks are
  replaced per update and released when removed or the runtime is destroyed.

The article's previous-frame input rectangles and next-frame application mutation
schedule are deliberate tradeoffs, not adopted here. Chroma preserves current input
geometry and fresh captured callbacks between coalesced events.

## Compatibility and application migration

An unmigrated primitive retains a named, counted compatibility adapter. Before input,
its legacy `draw` still runs into a discarded list. During presentation update, legacy
drawing runs once and captures commands; painting appends them without replaying
registration effects. This fallback is explicitly **not** paint-free.

All built-ins and the twelve relevant ShapeTree primitives use the separated path.
The companion patch moves viewport/focus/selection lifecycle into update, and raw
Escape/modal/press/release behavior into ordered input. It preserves 30-point sidebar
rows with 1-point spacing and visible-only expensive controls. It also removes a
quadratic metadata lookup: each row uses its existing session value instead of
searching the entire session collection again. Identity and lightweight metadata
still scan the full collection; no universal O(visible rows) claim is made.

Opt-in counters distinguish body evaluation, measurement/hits, placement, registration,
paint/commands, text layouts, named fallbacks and live transient nodes/subscriptions.
Timing disables instrumentation. See [results](RegistrationResults.md) and the
[requirement checklist](ArchitectureHandoffChecklist.md) for tests and limitations.
