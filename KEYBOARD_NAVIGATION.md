# Vim-Style UI Tree Navigation

## Current state

Chroma already has much of the runtime machinery needed for keyboard navigation:

- During drawing, interactive controls build a `FocusNode` tree containing nested
  groups and interactive leaves (`WidgetID`s).
- The active control is retained as an index path into that tree, for example
  `[0, 2, 1]`.
- Focus follows a stable `WidgetID` across relayout when possible.
- Pointer movement, clicking, and activation already use this tree.
- Both backends translate physical keys through `KeyBindings` into `Command`s.

What does not yet exist:

- Navigation commands beyond activation, submission, cancellation, and dismissal.
- Keyboard traversal over the focus tree.
- Functional scoped bindings from `KeyBindingBlock` / `.keyBindings { ... }`.
  At present, only `App.keyBindings` are installed in the render backends.

Relevant implementation areas:

- `Sources/Chroma/FocusTree.swift`
- `Sources/Chroma/Interaction.swift`
- `Sources/Chroma/Command.swift`
- `Sources/Chroma/KeyBindings.swift`
- `Sources/MetalBackend/MetalRenderer.swift`
- `Sources/WaylandBackend/WaylandKeyboard.swift`

## Recommended first increment: control-only navigation

Keep the current invariant that the cursor selects an interactive leaf, rather
than allowing it to stop on structural group nodes. This provides useful
navigation immediately without changing established focus, editing, rendering,
or activation semantics.

Suggested bindings:

| Key | Behavior |
| --- | --- |
| `j` / `k` | Next / previous interactive leaf in document order |
| `h` / `l` | Previous / next interactive sibling in the nearest focus group |
| `g` / `G` | First / last interactive leaf |
| `Enter` / `Space` | Existing activation behavior |

The exact interpretation of `h` and `l` can be adjusted, but document-order
`j`/`k` plus first/last navigation should form the useful baseline.

### Command model

Add an explicit navigation command type:

```swift
public enum NavigationCommand: Hashable, Sendable {
  case nextSibling
  case previousSibling
  case parent
  case firstChild
  case next
  case previous
  case first
  case last
}

public enum Command: Hashable, Sendable {
  case action(ActionCommand)
  case navigation(NavigationCommand)
  case editing(TextEditEvent)
  case application(CommandID)
}
```

`Interaction.apply(_:)` should resolve `Command.navigation` against the current
`FocusNode` tree and call the existing `moveCursor(to:)` only with a leaf path.

### Opt-in key binding preset

Vim navigation should not become a default binding. Provide an opt-in,
app-level preset instead:

```swift
var keyBindings: KeyBindings {
  .vimNavigation.overlay {
    // Application-specific bindings and overrides.
  }
}
```

A possible implementation of the preset is:

```swift
extension KeyBindings {
  public static let vimNavigation = KeyBindings {
    bind("j", to: .navigation(.next))
    bind("k", to: .navigation(.previous))
    bind("h", to: .navigation(.previousSibling))
    bind("l", to: .navigation(.nextSibling))
    bind("g", to: .navigation(.first))
    bind("g", modifiers: .shift, to: .navigation(.last))
  }
}
```

This is deliberately app-level until scoped key bindings are wired through the
rendering and interaction pipelines.

## Text editing behavior

Plain `h`, `j`, `k`, and `l` must remain normal text input while a `TextField`
is editing. The existing `KeyBindings.prefersTextInsertion` routing already
supports this: printable text takes precedence during editing unless the binding
is an editing command.

Thus an app-level vim navigation binding should navigate in movement mode while
preserving normal typing in a text field. Escape should retain its existing
editing/cancellation behavior.

## True DOM/tree cursor: later design option

A more literal DOM navigator would allow the cursor to select groups as well as
leaves:

| Key | Behavior |
| --- | --- |
| `h` | Parent group |
| `l` | First child |
| `j` / `k` | Next / previous sibling |
| `g` / `G` | Root / deepest last node |

This should be treated as a separate feature rather than folded into the first
increment. It needs product decisions and implementation support for:

- A visual selection indication for a group.
- Whether selecting a group clears control focus or editing.
- Whether and how `Enter` activates a group.
- Groups with no direct interactive descendants.
- Interaction with clipping, scroll views, and lazy virtualization.

Changing the current selected-leaf invariant without resolving these questions
would risk regressions in focus and text-editing behavior.

## Scroll views and lazy content

The focus tree only contains leaves materialized in the current frame. This is
particularly important for `LazyVStack`, which only builds visible rows.

Stage support as follows:

1. Navigate only among leaves currently materialized in the focus tree.
2. When an existing destination is selected, request scrolling to make it
   visible as necessary.
3. Later add collection-aware traversal APIs so a `LazyVStack` can identify,
   scroll to, and materialize the logical next/previous row.

This avoids claiming to traverse virtualized controls that do not currently
exist in the runtime focus tree.

## Implementation sequence

1. Add `NavigationCommand` and route it from `Interaction`.
2. Add `FocusNode` helpers for document-order next/previous, nearest-group
   sibling traversal, and first/last leaf lookup.
3. Add `KeyBindings.vimNavigation` as an opt-in preset.
4. Add tests covering nested groups, boundaries, focus persistence, activation
   after navigation, and text-field editing precedence.
5. Separately decide whether `.keyBindings { ... }` should become functional
   scoped binding infrastructure.

## Open decision

Choose the scope of the first implementation:

- **Control-only navigation (recommended):** navigate between interactive leaves
  and preserve the existing focus model.
- **True tree cursor:** navigate groups and leaves, with new visual and
  interaction semantics.
