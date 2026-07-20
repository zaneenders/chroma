/// The complete input language of the framework: six movement commands on
/// the focus tree plus activation.
///
/// UI is a tree — stacks are groups, interactive widgets are leaves — so all
/// navigation is expressed as movement on that tree, and every input device
/// compiles into these commands. The keyboard maps keys onto them directly
/// (the backend's keymap is the only device-specific piece); the pointer is
/// a macro generator, compiling hover and clicks into the move sequence that
/// would walk the cursor to the pointer's target (see ``Interaction``).
///
/// Widgets never see raw devices. There is exactly one cursor and one
/// language; shortcuts, skips, and chords are all expressible as sequences
/// of these commands.
public enum UICommand: Equatable, Sendable {
  /// Move to the previous sibling in a vertical group.
  case up
  /// Move to the next sibling in a vertical group.
  case down
  /// Move to the previous sibling in a horizontal group.
  case left
  /// Move to the next sibling in a horizontal group.
  case right
  /// Step into the selected group, selecting its first child.
  case `in`
  /// Step out to the selected node's parent group.
  case out
  /// Activate the selected widget: click it, press it, fire its action.
  case activate

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
    }
  }
}
