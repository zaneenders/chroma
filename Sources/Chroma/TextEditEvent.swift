public enum TextEditEvent: Hashable, Sendable {
  case insert(String)
  case backspace
  case deleteForward
  case moveCaretLeft
  case moveCaretRight
  case moveCaretUp
  case moveCaretDown
  case selectCaretLeft
  case selectCaretRight
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
