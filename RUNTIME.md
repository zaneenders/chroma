# Direct runtime

A window owns reusable layout buffers and a committed indexed interaction snapshot.
Its `build` closure constructs typed nodes; ordinary functions compose them.
There is no `Block` protocol, result builder, intermediate authoring tree, or
standalone rendering path.

```swift
host.build = { buffer, context in
  let title = buffer.text(Text("Hello"), context: context.keyed("title"))
  let saveButton = buffer.button(Button("Save", action: { print("Saved") }), context: context.keyed("save"))
  return buffer.stack([title, saveButton], axis: .vertical, spacing: 8, context: context)
}
```

`App` implements `build(into:context:)` with that same signature. Text, button,
editor and scroll values are plain configuration. Scroll row factories receive the
buffer and their final keyed context. Use distinct `keyed` child contexts for state
that must survive reordering; `childScope` gives explicit positional identity.
Duplicate interaction leaf IDs fail early instead of silently sharing callbacks.

## Update contract

`WindowRuntime` alone dispatches input. Every actionable event first commits current
callbacks and geometry; raw key resolution and delivery share that preparation.
`HeadlessHost.sendKeyboardInput` uses the same atomic raw-key dispatch as native hosts.
Input is applied once through a FIFO, including input queued before the first frame
and input sent from another event's callback. Both explicit and scheduled frames
drain pending events first. `HeadlessHost.render()` takes a snapshot; supplying its
optional input argument appends one event after already queued input. The producer then
commits and draws the current root, so an
action may replace it synchronously. Hover may use last-presented geometry.

Within the internal runtime/test lifecycle, construction and measurement precede
registration, then painting at the same rectangle. Hosts own that lifecycle. Drawing does not build nodes or replay input. `LayoutNode` is a checked
owner/generation/index handle, never persistent identity. Each node supports one
placement in the registered graph: emit distinct nodes for repeated content rather
than sharing a handle between parents or sibling positions. Reset destroys captures
and retains capacity. Committed interaction rows survive temporary layout storage;
render and navigation views link the same rows. Interaction selection and command scopes
retain ordinal paths. Keys preserve focus/editing across
reordering of realized content. Virtualizing an editor out of view ends its editing
session and clears selection; scrolling it back does not resume editing. Scroll
focus memory is retained separately.

Selectable text uses one read-only input/document selection path, including pointer-only
selection for navigation-ignored text. `TextSelectionManager` and `LayoutContext.selection`
are removed. Custom selectable leaves register with `textSelectionState` and paint with
`textInputVisualState`. Copy/select-all providers belong to the current registration and
must be installed by current content; removing that content removes its callbacks.

## Retained work

- Plain text caches exact UTF-8/wrapping results, capped at 512 entries and 4 MiB
  estimated storage. Oversized entries bypass retention.
- Keep `MarkdownDocument` in the model to reuse parsing and width/style-keyed wrapping.
  Two width/style slots retain per-block lines, copied text, and character offsets. Placement stays fresh. Markdown
  still emits all paragraph handles; it does not virtualize paragraphs.
- Uniform lists accept `identityRevision`; change it on every ID/order change,
  including same-count changes. Nil scans IDs. Row values and callbacks stay fresh.
- Variable lists reset one measurement buffer after each invalid row. Cold work is
  O(rows), but retained node capacity covers one row plus the visible window.
- Keyed scalar animation commits ownership during registration. Retargeting starts
  at the current value; removal or virtual eviction cancels it; scheduling stops at rest.

Large control payloads use side buffers. On x86_64 the common record is 112 bytes,
plus an 80-byte context and any child/measurement/payload entries. Metal/OpenGL use
the existing ordered `DrawList`; returned lists preserve value semantics.

CPU validation: `CHROMA_HEADLESS_ONLY=1 swift test -j 2`. This omits native backend
products for that invocation. Use the same setting for resolution/build/test;
SwiftPM replans when the manifest environment changes. Native presentation needs
separate validation. Existing Block-based apps must migrate to direct construction.
