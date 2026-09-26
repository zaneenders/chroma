# Keyboard navigation plan

## Updated interaction contract

The implementation now allows directional exits: search peers at the current level,
then outward through ancestors, stopping on the neighboring group without descending.
`l` on a leaf activates it or begins editing; Escape returns to MOVE. Groups remember
one selected child per level. ScrollView is a boundary; layout wrappers are not.
The workspace demo exercises session switching, retained drafts and history positions,
message actions, and explicit Latest scrolling. The original proposal below predates
these decisions; its sibling-only movement and leaf-entry no-op rules are superseded.

## Original proposal

The window is the root navigation group. `Group { ... }` creates an explicit level unless it has no selectable descendants; ignore empty groups. `VStack`, `HStack`, `ZStack`, `LazyVStack`, and other layout wrappers arrange content but do not create levels. Controls (and currently focusable content) are leaves. `ScrollView` creates a level, including when it contains a `LazyVStack`; the lazy stack must not create another level. No pass-through or `.ignore()` API for now.

Initially the window root is active and highlighted, with no selected child. The first directional key selects a child at the root without entering it; `l` and `s` do nothing until a child is selected. At the active level, `d`/`f`/`j`/`k` move among that level's selectable children; movement never enters or exits a group. Preserve the existing directional key mappings (`d` left, `f` up, `j` down, `k` right). `l` enters the selected group, restoring its last selection or selecting its first available child. `s` returns to the parent, leaving the group selected there. `l` on a leaf and `s` at the root do nothing. Activation and text editing continue to target leaves only; editing keys retain their current behavior. Pointer hover temporarily highlights the hovered item without changing keyboard selection; a click selects its leaf and enters its ancestor groups.

A selected group is **not** equivalent to its first leaf. Both the active level and the selected item need their own state and visual treatment.

## Proposed types

Sketches of the intended data boundaries, not drop-in implementations:

```swift
// Public API: grouping is independent of layout.
public struct Group: PrimitiveBlock {
  public var content: any Block

  public init(@BlockBuilder content: () -> TupleBlock)
  public var focusRule: FocusRule { get } // .container
  // Measure and draw content; register one navigation boundary with a stable WidgetID.
}

// Internal, derived from render-time registrations; does not own drawing or handlers.
struct NavigationNode {
  enum Kind {
    case group(WidgetID?) // nil is the window root
    case leaf(WidgetID)
  }

  var kind: Kind
  var rect: Rect // visible group bounds for highlight; viewport for root
  var children: [NavigationNode]
  // Retain enough layout-axis and position information for directional peer selection.
}

// Paths index the navigation tree, not the rendering tree.
struct NavigationSelection {
  var activeGroupPath: [Int] // [] means window
  var selectedChildIndex: Int? // nil initially at the root or when no child is selectable
}

struct NavigationState {
  var selection: NavigationSelection
  var lastSelectedChild: [WidgetID: WidgetID] // or stable child paths for non-leaf groups
}
```

Use `WidgetID` internally as today; do not make it public just to expose `Group`. Stable structural identity should survive insertions/reordering where the existing key mechanism supports it. Do not force `FocusTreeWalker`'s leaf-only `[Int]` path to represent a selected group: that currently drives leaf activation, `FocusTarget`, text editing, and reveal. Keep a separate navigation selection, then map to a render leaf only when needed. If the derived tree needs more layout metadata than shown, add it when tests reveal the need.

## Implementation slices

1. **Write contract tests.** Root with a leaf and two sibling groups, then a nested group and uneven rows: initially only the window is selected; the first directional key selects a root child; directional movement stays at its current level; `l`/`s` enter/exit exactly one level; selection returns to the group on exit; leaf activation cannot fire while a group is selected. Test hover without selection, pointer click selection, removal of the selected item, and ignored empty groups. Update existing scope tests that intentionally assert geometric jumps across boundaries rather than preserving those semantics.
2. **Add `Group` and derive the navigation tree.** Reuse `FocusNode` registrations, geometry, and `WidgetID`; flatten layout-only groups (including `LazyVStack`) when constructing navigation peers. Ignore explicit groups with no selectable descendants. Directional peer selection can use stack axes and geometry, but must treat nested navigation groups atomically. Avoid coupling traversal to rendered character/glyph nodes. Make the root viewport explicit rather than treating the root's current `.zero` rect as a visual boundary.
3. **Route input through `NavigationSelection`.** Implement sibling-only `dfjk`, hierarchical `s`/`l`, and memory per group. Update selection reconciliation after redraws to prefer stable IDs, with a deterministic nearby fallback. A pointer click inside a group should activate that group's ancestor chain and select the clicked leaf; programmatic `FocusTarget.focus()` should do likewise. Keep scoped command/key bindings attached to the selected path as appropriate; group selection must not activate the remembered leaf.
4. **Show the current level.** Paint one subdued outline around the active group (window edge at root) and a distinct selection indicator on its selected child, whether group or leaf. Initially show only the root outline. Do not show nested active outlines simultaneously. Hover temporarily highlights its target but does not change keyboard selection. Account for clipping and scroll viewport bounds.
5. **Dog-food a small demo** with adjacent groups, nested groups, and ordinary controls. Tune movement between uneven peers, outline contrast, and the initial root selection before committing to more policy.
6. **Integrate scroll and editing.** Treat `ScrollView` as the navigation group and `LazyVStack` as layout-only; preserve virtualized row reveal and focus memory without creating a second list level. Avoid selecting undrawn rows until they materialize. Ensure `s` from a deep list returns to the scroll group rather than a nearby outside leaf, and `l` restores the remembered row. Editing stays inside its leaf until the editing mode ends.

## Validation

Run focused walker/group, pointer, default-focus, text-input, and virtualized-list tests after each slice, then `swift test` and the Example tests. The first dog-food milestone is ordinary `Group` navigation plus visible level/selection; scroll virtualization follows once the interaction feels right.
