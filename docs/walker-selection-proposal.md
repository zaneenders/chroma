# Prepared tree walkers and document selection

Design sketch for discussion. Types below are pseudocode; omitted IDs, content
variants, geometry, and method bodies are deliberately unspecified.

## Update data

```swift
struct PreparedTree {
  let generation: Generation
  let root: Node
}

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

Prepare an ephemeral tree and fresh actions for each update. Content refers to
actions by ID; callbacks stay on the main actor.

```text
app state --prepare--> PreparedTree + Actions
                            |
                   measure / place
                            |
                         Geometry
                         /      \
                    InputMap   PaintList
```

Layout remains dependency-aware measure/place: parent proposals and child sizes
determine placement. A generic preorder walk does not replace that algorithm.
Reuse the existing layout and controller.

## Small read-only walkers

```swift
func walk<Output>(
  _ node: Node,
  into output: inout Output,
  visit: (Node, inout Output) -> Void
) {
  visit(node, &output)
  for child in node.children {
    walk(child, into: &output, visit: visit)
  }
}

// Optional rewriting is a separate operation, returning a copied tree.
func transform(_ tree: PreparedTree, using rewrite: (Node) -> Node) -> PreparedTree
```

Each pass owns its output; the input tree stays unchanged. Use concrete passes
for input, paint, and diagnostics. No generic scheduler.

Independent read-only passes may run in parallel only when their complete inputs
and outputs are immutable, Sendable values. Prepared data is not automatically
Sendable; generic Content is not assumed serializable. Keep actor-bound resources
and callbacks on the main actor. Apply results in order, for the matching
generation; discard stale results.

## Lifetime and input order

```text
event N -> state change -> fresh tree / actions / input geometry -> event N+1
                                |
                       presentation may coalesce
```

An update is not a displayed frame. Refresh input before the next event even
when presentation is deferred. Do not replay input against a later tree.

Discard superseded trees and action tables. Keep semantic state, focus, scroll,
and the geometry needed while the current update remains active.

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

## First change and regression coverage

Start with read-only text/Markdown, reuse layout/controller, then delete redundant
selection paths. Keep the scroll fix in [#85](https://github.com/zaneenders/chroma/pull/85) separate.

Minimum implementation regressions:
- Backward select -> anchor offscreen -> reverse/shrink.
- Copy with offscreen endpoints and intermediate runs.
- Endpoint deletion and document/editor session replacement.
- Unicode Character boundaries, resize, and rewrap.
- Fresh ordered input when presentation coalesces; reject stale generations.

This PR proposes the design only. It adds no implementation or executable tests.
