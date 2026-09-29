public enum TextMovementUnit: Hashable, Sendable {
  case character, word, vertical, document
}

public enum TextDirection: Hashable, Sendable {
  case backward, forward
}

public enum TextEditEvent: Hashable, Sendable {
  case insert(String)
  case move(TextMovementUnit, TextDirection, extendSelection: Bool)
  case delete(TextMovementUnit, TextDirection)
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

extension TextEditEvent {
  var movement: (TextMovementUnit, TextDirection, Bool)? {
    switch self {
    case .move(let unit, let direction, let extend): (unit, direction, extend)
    case .moveCaretLeft: (.character, .backward, false)
    case .moveCaretRight: (.character, .forward, false)
    case .moveCaretUp: (.vertical, .backward, false)
    case .moveCaretDown: (.vertical, .forward, false)
    case .selectCaretLeft: (.character, .backward, true)
    case .selectCaretRight: (.character, .forward, true)
    case .selectCaretUp: (.vertical, .backward, true)
    case .selectCaretDown: (.vertical, .forward, true)
    case .moveCaretToStart: (.document, .backward, false)
    case .moveCaretToEnd: (.document, .forward, false)
    default: nil
    }
  }

  var deletion: (TextMovementUnit, TextDirection)? {
    switch self {
    case .delete(let unit, let direction): (unit, direction)
    case .backspace: (.character, .backward)
    case .deleteForward: (.character, .forward)
    default: nil
    }
  }
}
