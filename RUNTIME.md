# One layout runtime

A window owns one noncopyable `LayoutBuffer`. Blocks and `DirectLayout` lower into
that buffer. Plain leaves and stacks are typed records, not classes with closure
fields. Custom preparation can append callbacks that receive `inout LayoutBuffer`.
`LayoutNode` is an owner/generation/index handle; it is not a persistent widget ID.

At each update the runtime prepares current content, lays out and registers it,
then optionally writes an ordered `DrawList`. Actionable input refreshes before
being applied exactly once, including between events whose drawing is coalesced.
Raw-key resolution and delivery share one scoped preparation. Hover may use the
previous geometry. Drawing never dispatches actions. App state read during drawing
still participates in observation.

Reset destroys operation payloads and measurements but preserves buffer capacity.
Replacing the window root releases capacity, registrations and caches. Measurements
and stack placements are shared only within that operation; fresh callbacks are
never inferred from a key or dirty flag. Returned draw lists have value semantics:
reusing command storage cannot change a previous frame. Metal and OpenGL still
consume the same ordered commands and clip operations.

## Direct construction

```swift
DirectLayout { buffer, context in
  let title = buffer.prepare(Text("Hello"), context: context.keyed("title"))
  let button = buffer.prepare(Button("Save", action: save), context: context.keyed("save"))
  return buffer.stack([title, button], axis: .vertical, spacing: 8, context: context)
}
```

`VStack`/`HStack` builders emit that same stack record. Keys must be unique among
siblings. Use `context.childScope(index)` for fixed positional children; use
`context.keyed(id)` or Block `.id(id)` for movable children. Focus, editing and
scroll state remain attached to those logical identities, independently of slots.
Virtual lists retain only the existing bounded navigation metadata.

## Custom preparation migration

`BlockEngine.Resolved` is removed. A `LayoutPreparingBlock` now implements:

```swift
func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
  let child = buffer.prepare(content, context: context)
  return buffer.append(
    child: child,
    register: { buffer, rect in buffer.register(child, in: rect) },
    paint: { buffer, list, rect in buffer.paint(child, into: &list, in: rect) })
}
```

For a standalone operation, `var prepared = BlockEngine.prepare(block, context: context)`
owns the buffer. Its measure/register/paint methods mutate that noncopyable owner.
Handles cannot outlive reset or move between buffers. Callbacks may append nodes;
they must not reset or replace the buffer. No unsafe arena or experimental lifetime
annotations are needed. Storage uses the already-pinned swift-collections 1.7.1
`UniqueArray`; the owner is `~Copyable` so escaping callbacks cannot capture it.

## Reusable content

- Text shaping is shared per window by exact UTF-8 content and wrapping columns.
  It retains at most 512 entries and 4 MiB of estimated text/line storage; oversized
  layouts bypass retention. Positions, scale, metrics and callbacks stay current.
  The byte budget is accounting, not a measured heap-byte guarantee.
- Keep `MarkdownDocument(source)` in the model and render `MarkdownText(document)`.
  Assign or append to `document.markdown` to reparse. Its revision changes only when
  source bytes change. `MarkdownText(string)` is a convenience resource allocation.
  The previous `MarkdownText.markdown` property is now `document.markdown`.
- Identified uniform `ScrollView` accepts `identityRevision`. Reuse skips ID scans;
  bump it for every ID/order change, even at unchanged count. Current row values
  and actions are rebuilt independently. Omit it to validate IDs on each use.
- `AnimatedValue(target, duration: 0.2) { value in ... }` samples one scalar for
  layout, registration and drawing. Stable keys preserve progress; retargeting
  starts from the current value. First mount starts at target. Removal or virtual
  eviction cancels the transition, and the scheduler stops at rest. Measurement
  and drawing alone do not commit animation state.

## Validation

```sh
CHROMA_HEADLESS_ONLY=1 swift test -j 2
CHROMA_HEADLESS_ONLY=1 swift run --package-path Benchmarks -c release LayoutBenchmark
```

`PipelineMetrics.layoutNodes` counts emitted records; `bufferGrowths` counts
capacity growth events, not total allocations. Observation lifetime counters remain;
resolved-class lifetime counters are removed. Cold capacity growth, warm reuse and
retained text resources are deliberately separate from malloc/CPU measurements.
