public enum NavigationCommand: Hashable, Sendable {
  case up
  case down
  case left
  case right
  case `in`
  case out
  case next
  case previous
  case first
  case last
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
  case application(CommandID)
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

/// Compatibility vocabulary for code which injects commands directly into an `InputState`.
/// New key bindings and handlers should use `Command`.
public enum UICommand: Equatable, Sendable {
  case up, down, left, right, `in`, out, activate
  case nextLeaf, previousLeaf
  case pageUp, pageDown, home, end

  public var command: Command {
    switch self {
    case .up: .navigation(.up)
    case .down: .navigation(.down)
    case .left: .navigation(.left)
    case .right: .navigation(.right)
    case .in: .navigation(.in)
    case .out: .navigation(.out)
    case .activate: .action(.activate)
    case .nextLeaf: .navigation(.next)
    case .previousLeaf: .navigation(.previous)
    case .pageUp: .navigation(.pageUp)
    case .pageDown: .navigation(.pageDown)
    case .home: .navigation(.home)
    case .end: .navigation(.end)
    }
  }

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
