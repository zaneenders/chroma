public enum NavigationCommand: Hashable, Sendable {
  case up
  case down
  case left
  case right
  case `in`
  case out
  case next
  case previous
  case pageUp
  case pageDown
  case home
  case end
}

public enum ActionCommand: Hashable, Sendable {
  case activate
  case submit
  case cancel
  case dismiss
}

public struct CommandID: Hashable, Sendable, ExpressibleByStringLiteral {
  public let rawValue: String

  public init(_ rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }
}

public enum Command: Hashable, Sendable {
  case navigation(NavigationCommand)
  case action(ActionCommand)
  case editing(TextEditEvent)
  case application(CommandID)
}

extension Command {
  /// Short name used by interaction diagnostics (e.g. `lastMacroDescription`).
  package var label: String {
    switch self {
    case .navigation(.up): "up"
    case .navigation(.down): "down"
    case .navigation(.left): "left"
    case .navigation(.right): "right"
    case .navigation(.in): "in"
    case .navigation(.out): "out"
    case .navigation(.next): "next"
    case .navigation(.previous): "prev"
    case .navigation(.pageUp): "page-up"
    case .navigation(.pageDown): "page-down"
    case .navigation(.home): "home"
    case .navigation(.end): "end"
    case .action(.activate): "activate"
    case .action(.submit): "submit"
    case .action(.cancel): "cancel"
    case .action(.dismiss): "dismiss"
    case .editing(.insert): "insert"
    case .editing(.backspace): "backspace"
    case .editing(.deleteForward): "delete-forward"
    case .editing(.moveCaretLeft): "caret-left"
    case .editing(.moveCaretRight): "caret-right"
    case .editing(.moveCaretUp): "caret-up"
    case .editing(.moveCaretDown): "caret-down"
    case .editing(.selectCaretUp): "select-caret-up"
    case .editing(.selectCaretDown): "select-caret-down"
    case .editing(.moveCaretToStart): "caret-start"
    case .editing(.moveCaretToEnd): "caret-end"
    case .editing(.selectAll): "select-all"
    case .editing(.copy): "copy"
    case .editing(.cut): "cut"
    case .editing(.paste): "paste"
    case .editing(.submit): "submit"
    case .editing(.endEditing): "end-editing"
    case .application(let id): id.rawValue
    }
  }
}

public enum CommandResult: Sendable {
  case handled
  case ignored
}

public enum ActionRole: Hashable, Sendable {
  case normal
  case defaultAction
  case cancel
  case destructive
}
