public enum UICommand: Equatable, Sendable {
  case up
  case down
  case left
  case right
  case `in`
  case out
  case activate
  case nextLeaf
  case previousLeaf
  case pageUp
  case pageDown
  case home
  case end

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
