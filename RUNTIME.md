# One construction and execution path

The runtime owns a reusable `LayoutBuffer` and a committed indexed interaction
snapshot. A root `LayoutBuilder` writes typed nodes directly; optional `Block`
authoring values implement only `emit(into:context:)` and use those same methods.
There is no associated `Body`, primitive/prepared protocol hierarchy, or second
standalone owner. Compose custom UI with ordinary functions.

```swift
host.build = { buffer, context in
  let title = buffer.text(Text("Hello"), context: context.keyed("title"))
  let saveButton = buffer.button(Button("Save", action: save), context: context.keyed("save"))
  return buffer.stack([title, saveButton], axis: .vertical, spacing: 8, context: context)
}
```

`host.setContent(VStack { ... })` is optional authoring convenience. It installs a
root construction function, not another execution path. `BlockBuilder` collects
children; keyed collections emit fragment records. Unary typed operations distribute
across those fragments without a second protocol-based flattening system.

## Update contract

Every actionable event first commits current callbacks and geometry. Raw key
resolution and delivery share that preparation. The event is applied exactly once;
drawing cannot replay it. Hover may use last-presented geometry. Commit and drawing
share rectangles, clipping and painter order. Built-in drawing never builds nodes. `WindowRuntime` alone dispatches input; the
producer only commits registrations and draws the root current after dispatch.

`LayoutNode` is an owner/generation/index handle, not persistent widget identity.
Reset destroys captures but keeps buffer capacity. Large control payloads use
side buffers; the common record and context occupy 112 and 80 bytes on x86_64. Keys own focus, editing, scroll
and animation state. Committed interaction rows outlive temporary layout storage;
render and navigation views link the same rows. Root replacement clears both.

For low-level tests/tools: create one buffer, emit a root, measure as needed, then
register and paint at the same rectangle. Painting before registration is invalid.
The window handles this lifecycle. `BlockEngine`, `PreparedLayout`,
`PaintableBlock` and `LayoutPreparingBlock` are removed.

## Reusable content

- Plain text uses an exact UTF-8/wrapping cache: 512 entries and 4 MiB estimated
  storage. Oversized layouts bypass retention. Geometry and callbacks stay fresh.
- Keep `MarkdownDocument` in the model. Source changes replace its parsed snapshot
  and revision-keyed wrap cache. Two layout-input slots reuse per-block plans;
  placement geometry is rebuilt. No callbacks are cached. `MarkdownText` still
  emits all block handles; it does not virtualize paragraphs.
- Uniform lists accept `identityRevision`; bump it on every ID/order change, even
  at fixed count. Nil scans IDs. Row values and callbacks remain current.
- Variable lists reuse one controller-owned measurement buffer, reset after each
  invalid row. Cold measurement is O(rows), but retained node capacity is bounded
  by one row plus the visible window, rather than the full dataset.
- Keyed scalar animation samples one time per update and commits ownership only
  during registration. Retargeting starts at the current value. Removal or virtual
  eviction cancels it; the scheduler stops at rest.

Metal/OpenGL consume the same ordered `DrawList`. Returned lists retain value
semantics when scratch storage is reused. CPU checks use
`CHROMA_HEADLESS_ONLY=1 swift test -j 2`; native presentation is separate validation.
