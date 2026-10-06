# Prepared tree walkers and document selection

Implemented baseline. The sketches below describe ownership; concrete APIs and
regression coverage are listed at the end. Parallel passes and tree rewriting
remain optional extensions, not runtime requirements.

## Update data

```swift
struct PreparedTree { let generation: Generation; let root: Node }
struct Node {
  let id: BlockID                 // stable semantic identity
  let content: Content
  let children: [Node]
}
@MainActor struct Actions {
  let generation: Generation
  let handlers: [ActionID: @MainActor () -> Void]
}
```

Fresh resolve/parse creates a tree and actions for each relevant operation.
Content refers to actions by ID; callbacks stay on the main actor. Share the
tree only within that update, then discard it. No prepared graph caching across
updates, dirty-node tracking, or cache-validity engine.

```text
model --resolve/parse--> PreparedTree + Actions
                              |
                     measure / place
                              |
                           Geometry
                           /      \
                      InputMap   PaintList
```

Layout remains dependency-aware measure/place: parent proposals and child sizes
determine placement. A generic preorder walk does not replace it. Reuse the
existing layout and controller; run only the passes needed by the operation.

## Small read-only walkers

```swift
func walk<Output>(
  _ node: Node, into output: inout Output,
  visit: (Node, inout Output) -> Void
) {
  visit(node, &output)
  for child in node.children { walk(child, into: &output, visit: visit) }
}

// Optional rewrite returns a copied tree.
func transform(_ tree: PreparedTree, using rewrite: (Node) -> Node) -> PreparedTree
```

Most walkers read unchanged input and accumulate their own output. Start with
serial concrete passes, no generic scheduler. Independent pure passes may later
parallelize with immutable Sendable inputs and isolated Sendable outputs.
Prepared data is not automatically Sendable; generic Content is not assumed
serializable. UI callbacks stay on the main actor. If asynchronous outputs are
used, apply in order for the matching generation and reject stale results.
Generation identifies an operation; it is not a cache-validity mechanism.

## One UI owner, separate update and draw

```text
asynchronous input -> ordered main-actor queue
  event N -> fresh resolve -> layout/input -> dispatch once -> mutate model
  event N+1 -> fresh resolve -> layout/input -> dispatch once -> mutate model
                                                    |
                                           request presentation
                                                    |
  capped 30/60 Hz, when requested: fresh resolve -> layout/paint -> draw
```

- One serial UI owner orders dispatch and mutations exactly once. Input-only
  updates do no paint. Each actionable event gets fresh actions and geometry.
- Draw resolves post-action state. Never paint a pre-action snapshot after
  dispatch and call it current. Coalesce presentation requests, never actions.
- Observation notifications, async results applied to the model, animation
  ticks, first frame, and resize all request this same update/presentation path.
- The runtime observes dependencies and rearms Observation during evaluation.
  Notifications schedule work on the main actor after mutation completes;
  `@Observable` alone is not a scheduler.
- Cap presentation at the chosen 30/60 Hz rate. Idle means no work; active
  animation ticks request frames through the same path.
- Between operations, retain semantic state, selection, focus, scroll, and
  installed interaction output/geometry as needed. Never retain a prepared UI
  tree for the next operation.

Baseline: fresh resolve unconditionally for each input update and requested
presentation. Frame-only parsing is a possible later alternative only with
semantic commands that read current state; geometry-dependent consecutive
events can still require fresh layout between dispatches.

## Selection belongs to the document

```swift
enum TextOwner { case document(DocumentID), editor(EditorID) }
struct Position { let run: RunID; let offset: Int } // Character boundary
struct Selection { let owner: TextOwner; let anchor: Position; var active: Position }
struct TextRun { let id: RunID; let text: String }
struct Document {
  let owner: TextOwner
  let revision: Revision
  let runs: [TextRun]             // complete, ordered; stable run IDs
}
```

The app supplies the complete document independently of the virtualized block
tree, including explicit text/separators for copying. Positions use Character
offsets, not byte offsets. Visible text geometry maps back to run positions.
Navigation focus remains separate from selection ownership.

```text
document:  A (anchor) ---- B ---- C ---- D (active)
viewport:               [ B ---- C ]
copy:      A ================================= D
highlight:               B ==== C
```

Copy the entire selected document range, including offscreen runs; highlight its
intersection with visible geometry. Normalize anchor/active only to compute the
range. Reversing or shrinking moves active; it never replaces anchor.

- Offscreen endpoints and resize/rewrap preserve selection.
- An actually deleted endpoint or replaced document/editor session clears it.
- A missing virtualized node is not deletion; check the complete document.
- On text changes, use a known edit mapping or conservatively clear affected
  selection. Stable IDs alone cannot remap offsets across revisions.

## Implementation and regression coverage

Read-only text/Markdown share document selection, while editor selection remains
local to its editing session. Layout and the controller are reused. The scroll
ownership fix in [#85](https://github.com/zaneenders/chroma/issues/85) remains separate.

Covered regressions:
- Backward select -> anchor offscreen -> reverse/shrink.
- Copy with offscreen endpoints and intermediate runs.
- Endpoint deletion and document/editor session replacement.
- Unicode Character boundaries, resize, and rewrap.
- Fresh ordered, exactly-once input when presentation coalesces; post-action paint.
- Observation rearming, async model changes, animation, first frame/resize, and idle.
- No prepared-tree reuse between operations; reject stale asynchronous outputs.

### Concrete API

Supply a complete `TextDocument` outside the virtualized tree. Its ID identifies
one document session; each ordered run has a stable `TextID`, text, and the exact
separator copied before the next run. Offsets count Swift `Character` values.

```swift
let document = TextDocument(
  id: TextID(sessionID), revision: revision,
  runs: messages.map {
    .init(id: TextID($0.id), text: MarkdownText.plainText($0.markdown), separator: "\n\n")
  })

ScrollView(data: messages, rowHeight: 100, controller: controller) { message in
  MarkdownText(message.markdown).textRun(TextID(message.id))
}.textDocument(document)
```

Every visible fragment must match its run's text. `.textRun(id, offset:)` maps a
fragment into a larger run. `MarkdownText` maps its semantic blocks automatically;
`plainText` supplies the matching, width-independent copy representation. Use
`.id(sessionID)` to distinguish replacement editor sessions at the same position.

`BlockContext.selection` exposes the single read-only selection manager. Plain
selectable text and custom `textSelectionState` renderers without an explicit
document retain implicit tree-order selection for nonvirtualized content. They
cannot infer offscreen text; virtualized content must provide a complete document.

Changed document text, order, separators, revision, deleted endpoints, or a new
session clear selection conservatively. Resize and rewrap do not. External editor
text replacement clears its selection instead of guessing an offset mapping.

### Runtime

- `BlockEngine.Resolved` remains main-actor, operation-local prepared data.
  Dependency-aware layout is unchanged; read-only focus-tree walkers collect
  semantic text independently of paint. Interaction callbacks stay in the
  main-actor registration output, indexed by semantic widget IDs.
- Variable-height rows resolve and measure fresh each operation, sharing those
  results through registration and paint. Persistent row validity tracking and
  explicit `invalidateMeasurement()` were removed. Only installed row geometry
  survives; uniform-height rows still construct only the visible window.
- `WindowRuntime` serializes native, queued, batched, and reentrant inputs.
  Registration-only input updates never paint. Presentation resolves post-action
  state, reconciles selection, then paints once through the existing scheduler.
- Observation rearms on evaluation. Its asynchronous notifications carry an
  operation generation and are rejected after a newer evaluation or reset. No
  asynchronous layout/paint jobs or generic pass scheduler are introduced.

Regression suites: `TextDocumentTests`, `DocumentSelectionTests`,
`MarkdownDocumentRegressionTests`, `PreparedUpdateRegressionTests`,
`FreshRowLayoutTests`, plus the existing observation, input, layout, and scheduler
suites. Run `swift test` on each supported platform; Metal tests require macOS.
