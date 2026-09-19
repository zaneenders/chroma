# Keyboard Navigation Refactor

## Goal

Replace traversal-oriented navigation (`next`, `previous`, `first`, and `last`) with commands that describe the visible and structural UI:

- `up`
- `down`
- `left`
- `right`
- `inward`
- `outward`

Centralize traversal in a path-based focus-tree walker instead of continuing to add navigation rules to `FocusNode` and `Interaction`.

## Principles

- Navigation follows the authored `VStack` and `HStack` structure.
- The navigation cursor may select a group or an interactive leaf.
- Control focus and text-editing focus remain leaf-only concerns.
- Navigation does not flatten or copy the tree.
- Invalid or unavailable movement leaves the cursor unchanged.
- Vim key bindings remain opt-in.
- Only controls materialized in the current focus tree are navigable.

## Command model

Replace the current navigation cases with:

```swift
public enum NavigationCommand: Hashable, Sendable {
  case up
  case down
  case left
  case right
  case inward
  case outward
}
```

Use `inward` and `outward` in Swift because `in` is a language keyword. UI documentation may call them “in” and “out.”

Initial opt-in bindings:

| Key | Command |
| --- | --- |
| `k` / Up Arrow | `up` |
| `j` / Down Arrow | `down` |
| `h` / Left Arrow | `left` |
| `l` / Right Arrow | `right` |
| configurable | `inward` |
| configurable | `outward` |
| Enter / Space | activate a selected leaf |

The exact default keys for `inward` and `outward` should be chosen before exposing the preset as stable API.

## Cursor and focus

Introduce a navigation cursor represented by an index path from the focus-tree root:

```swift
struct FocusTreeWalker {
  let root: FocusNode
  private(set) var path: [Int]

  mutating func move(_ command: NavigationCommand) -> Bool
}
```

The path can identify either a group or a leaf.

Keep these concepts separate:

- **Navigation selection:** the walker path; may identify a group or leaf.
- **Focused control:** the selected interactive leaf, if any.
- **Editing state:** active only for an editable leaf.

Selecting a group must not activate it or begin editing. Activation is a no-op unless the navigation cursor identifies an interactive leaf.

When navigation moves from one leaf to another, update control focus through the existing cursor-movement path. When it moves to a group, clear leaf-specific focus and editing state without treating the group as a control.

## Structural movement rules

### Left and right

1. Walk from the selection toward the root until reaching the nearest horizontal group containing the selection.
2. Move to its previous or next child.
3. Attempt to replay the relative descendant path in the destination subtree.
4. If that path is unavailable, choose the nearest selectable descendant according to a deterministic fallback.
5. If there is no sibling in that direction, do not move.

### Up and down

Apply the same algorithm using the nearest vertical group.

This allows movement between nested rows or columns while preserving the selected position when their structures are similar.

### Inward

- If a group is selected, select its first selectable direct child.
- If a leaf or empty group is selected, do not move.
- Do not recursively skip multiple structural levels; repeated `inward` commands make hierarchy visible to the user.

### Outward

- Select the current node’s parent group.
- Do not move beyond the focus-tree root.

### Destination fallback

When replaying a relative path into an adjacent subtree:

1. Follow matching child indices while they remain valid.
2. Stop at the deepest valid selectable node.
3. Prefer the edge child facing the movement origin when the desired index does not exist.
4. Never search outside the chosen sibling subtree.

Implement and test this policy in the walker rather than in `Interaction`.

## Walker implementation

Keep `FocusNode.children` and the walker path as `Array`.

Avoid temporary path allocations such as:

```swift
Array(path.prefix(depth))
parentPath + [siblingIndex]
```

Instead:

- mutate one path with `append`, `removeLast`, and indexed replacement;
- reserve capacity when a temporary ancestor stack is necessary;
- inspect nodes by walking the existing path;
- avoid producing a flattened leaf list;
- avoid parent references and reference cycles.

Swift Collections is not needed for this traversal. `Deque`, `OrderedDictionary`, and tree collections do not improve an end-mutated, shallow index path. Reconsider an additional collection type only if profiling identifies a different access pattern.

## Selection persistence

Leaves continue to restore selection using `WidgetID`.

Groups currently have no stable identity. For the first implementation:

- retain a selected group by path when that path still identifies a compatible group after rebuilding;
- otherwise move to the nearest valid ancestor group;
- if no valid path remains, fall back to the first selectable node;
- do not introduce group IDs until a demonstrated relayout case requires them.

This keeps the refactor small while making group-selection behavior deterministic.

## Interaction integration

`Interaction` should:

1. Build the focus tree as it does now, retaining stack axis metadata.
2. Restore or validate the navigation path after each rebuild.
3. Construct a walker for a navigation command.
4. Ask the walker to move.
5. Apply the resulting path through one selection-update function.
6. Keep editing commands and printable text routing unchanged.
7. Ignore structural navigation while text editing is active unless an explicit mode transition exits editing first.

`Interaction` should not contain per-direction traversal algorithms.

## Visual treatment

Before enabling `inward` and `outward` in the demo, add a minimal indication for selected groups. It must be visually distinct from leaf focus and must not imply that the group can be activated.

Keep rendering work proportional to the selected node: one additional outline or equivalent primitive, with no full-tree overlay pass.

## Refactor sequence

### 1. Lock down semantics

- Choose bindings for `inward` and `outward`.
- Confirm that group selection clears editing.
- Confirm the fallback behavior for uneven sibling subtrees.
- Add focused tests expressing those decisions before changing integration code.

### 2. Add the walker

- Introduce `FocusTreeWalker` as an internal value type.
- Move ancestor, sibling, child, and relative-path traversal into it.
- Test it directly with hand-built horizontal, vertical, nested, uneven, and empty trees.
- Keep the existing commands temporarily so behavior can be compared during migration.

### 3. Separate navigation selection from leaf focus

- Permit the navigation path to identify groups.
- Centralize selection changes in `Interaction`.
- Preserve current leaf activation and editing behavior.
- Add restoration tests for tree rebuilds and removed nodes.

### 4. Replace commands

- Replace `nextSibling`, `previousSibling`, `parent`, `firstChild`, `next`, `previous`, `first`, and `last` with the six directional commands.
- Route commands through the walker.
- Remove superseded traversal helpers from `FocusNode`.

### 5. Update bindings and demo

- Update `KeyBindings.vimNavigation`.
- Preserve printable-key insertion while editing.
- Add group selection rendering.
- Update demo guidance and keyboard-navigation documentation.

### 6. Validate and simplify

- Remove migration-only code and duplicated tests.
- Run formatting and diff checks.
- Run the package test suite.
- Build the example package.
- Profile only if synthetic broad or deep trees expose a measurable issue.

## Test matrix

### Walker unit tests

- Horizontal movement among direct leaves.
- Vertical movement among direct leaves.
- Movement between nested sibling groups.
- Relative descendant-path preservation.
- Uneven destination subtree fallback.
- Empty groups.
- Boundary movement leaves the path unchanged.
- Repeated inward and outward movement.
- Root outward movement.
- Invalid initial paths.

### Interaction tests

- Leaf-to-leaf navigation updates focus.
- Leaf-to-group navigation clears leaf-only state.
- Group-to-leaf navigation restores leaf focus.
- Activation only affects selected leaves.
- Editing blocks navigation and preserves text insertion.
- Pointer selection and keyboard selection remain synchronized.
- Selection restoration survives equivalent rebuilds.
- Removed selected nodes use the documented fallback.

### Binding tests

- Every configured chord resolves to the intended command.
- Printable Vim keys insert text while editing.
- Arrow keys remain commands while editing only when explicitly intended.
- Application overlays can override the preset.

## Performance expectations

A structural move should inspect only:

- the current path’s ancestors, and
- one destination subtree path.

Expected cost is `O(depth)` for ordinary movement, with `O(destination subtree depth)` fallback. Memory remains `O(depth)`. Navigation runs on input events rather than every frame, so no spatial index, flattened traversal cache, or external collection dependency is planned.

The focus tree continues to be rebuilt as part of rendering. The refactor should not add a second tree, parent pointers, or a whole-tree navigation pass.

## Deferred work

- Geometric nearest-neighbor navigation.
- Navigation into non-materialized lazy content.
- Automatic scrolling to reveal a destination.
- Stable identities for structural groups.
- Functional scoped `.keyBindings`.
- Wrapping and grid-specific navigation policies.
