/// The complete input language of the framework: movement commands on the
/// focus tree plus activation.
///
/// UI is a tree — stacks are groups, interactive widgets are leaves — so all
/// navigation is expressed as movement on that tree, and every input device
/// compiles into these commands. The keyboard maps keys onto them directly
/// (the backend's keymap is the only device-specific piece); the pointer is
/// a macro generator, compiling hover and clicks into the move sequence that
/// would walk the cursor to the pointer's target (see ``Interaction``).
///
/// Directional movement is flattened: a strict sibling move applies when it
/// can, otherwise the command bubbles up to the nearest ancestor where it
/// does apply, and if nothing applies the cursor wraps around the tree's
/// leaf order — so a directional keypress always moves somewhere.
/// ``nextLeaf`` / ``previousLeaf`` skip the tree structure entirely and
/// cycle the leaves in depth-first (document) order, wrapping at the ends.
///
/// Widgets never see raw devices. There is exactly one cursor and one
/// language; shortcuts, skips, and chords are all expressible as sequences
/// of these commands.
public enum UICommand: Equatable, Sendable {
  /// Move to the previous sibling in a vertical group, bubbling up and
  /// wrapping when no such move applies.
  case up
  /// Move to the next sibling in a vertical group, bubbling up and
  /// wrapping when no such move applies.
  case down
  /// Move to the previous sibling in a horizontal group, bubbling up and
  /// wrapping when no such move applies.
  case left
  /// Move to the next sibling in a horizontal group, bubbling up and
  /// wrapping when no such move applies.
  case right
  /// Step into the selected group, selecting its first child.
  case `in`
  /// Step out to the selected node's parent group.
  case out
  /// Activate the selected widget: click it, press it, fire its action.
  case activate
  /// Move to the next leaf in depth-first order, wrapping at the end.
  case nextLeaf
  /// Move to the previous leaf in depth-first order, wrapping at the start.
  case previousLeaf
  /// Scroll the active viewport upward by approximately one page.
  case pageUp
  /// Scroll the active viewport downward by approximately one page.
  case pageDown
  /// Scroll the active viewport to its beginning.
  case home
  /// Scroll the active viewport to its end.
  case end

  /// A short lowercase name, joined into macro descriptions for display.
  public var label: String {
    switch self {
    case .up: "up"
    case .down: "down"
    case .left: "left"
    case .right: "right"
    case .in: "in"
    case .out: "out"
    case .activate: "activate"
    case .nextLeaf: "next"
    case .previousLeaf: "prev"
    case .pageUp: "page-up"
    case .pageDown: "page-down"
    case .home: "home"
    case .end: "end"
    }
  }
}
