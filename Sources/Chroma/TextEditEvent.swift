/// A text-editing operation. Bound to keys via `Command.editing`, translated by
/// backends, and delivered to editable controls in `InputState.textEvents`.
///
/// `copy`, `cut`, and `paste` are intercepted by backends (which own the
/// pasteboard) and never reach editable controls.
public enum TextEditEvent: Hashable, Sendable {
  case insert(String)
  case backspace
  case deleteForward
  case moveCaretLeft
  case moveCaretRight
  case moveCaretUp
  case moveCaretDown
  case selectCaretUp
  case selectCaretDown
  case moveCaretToStart
  case moveCaretToEnd
  case selectAll
  case copy
  case cut
  case paste
  case submit
  case endEditing
}
