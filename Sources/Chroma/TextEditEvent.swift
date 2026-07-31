public enum TextEditEvent: Equatable, Sendable {
  case insert(String)
  case backspace
  case deleteForward
  case moveCaretLeft
  case moveCaretRight
  case moveCaretToStart
  case moveCaretToEnd
  case submit
  case endEditing
}
