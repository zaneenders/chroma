# Identified collections

Uniform-height identified `ScrollView` virtualizes visible row content, but its default initializer validates every element ID on each construction. This remains the safe default for arbitrary collections, including mutable reference-backed collections.

For a model that already tracks structural changes, pass an explicit contract:

```swift
ScrollView(
  data: model.items, rowHeight: 24, controller: controller,
  identityRevision: .init(source: model.collectionID, revision: model.structureRevision)
) { item in
  Button(item.title) { model.open(item.id) }
}
```

The same argument is available after `selection:` on the logical-selection initializer.

## Contract

- `source` identifies one logical collection. Give unrelated or replaced sources distinct values, even when their revision numbers happen to match. Source and revision values must have stable equality while cached.
- Change `revision` whenever the ordered ID sequence changes: insert, remove, reorder, or replace IDs. This includes same-count mutations and changes to IDs stored in reference objects. A reused source/revision pair must always mean the same ordered IDs; a different slice needs a different revision or source if its ID sequence differs.
- Content-only changes do not need a structural revision. Current data, row bodies, callbacks, layout, and registration are still resolved normally. This contract caches only IDs and their lookup index, never row content or geometry.
- Do not reuse a revision for a different ID sequence. Correctness cannot be checked without the scan this opt-in skips. If the model cannot guarantee the contract, omit `identityRevision`.

The controller retains one current identity snapshot. A matching source, revision, ID type, and count reuses it without reading element IDs. A changed contract rebuilds the snapshot and checks duplicate IDs. The inexpensive count check is defensive; it does not make unchanged revisions safe after equal-count mutations. Omitting the contract performs the original full validation and clears the remembered contract. Older live views keep their own immutable snapshot, so a newly constructed list does not alter an older view's selection callbacks.

The first construction and each structural update remain O(n) and retain O(n) ID metadata. Repeated construction with an unchanged explicit contract avoids that collection-wide work. Source/revision comparison cost is the cost of comparing the supplied values; use small stable keys.

## Verification

`UniformRowIdentityTests` counts ID reads to verify zero reads on unchanged explicit revisions, conservative fallback, and rebuilding after mutations. Other regressions cover duplicate diagnostics, source/ID type distinctions, slices/noncontiguous storage, offscreen navigation, retained selection snapshots, and current callbacks between coalesced inputs.

`InputFrameBenchmark` reports unkeyed, conservatively identified, and explicitly revisioned cases on matching row counts. `StressBenchmark --identity-revisions 1` opts immutable fixture collections into the contract; the default `0` retains full scans. Reports include this mode in configuration and use schema/fixture version 2. Cross-mode timing comparisons are deliberate experiments; `CompareBenchmarks` rejects mismatched configurations. Headless timings exclude native dispatch, scheduling, renderer encoding, and GPU execution.
