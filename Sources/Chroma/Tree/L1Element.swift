/// ``L1Element`` reduces the number of node types in a tree in order to be
/// flattened further.
indirect enum L1Element {
  case text(String)
  case input(L1Element, handler: InputHandler)
  case group([L1Element])
}

extension L1Element {
  func toL2Element() -> L2Element {
    switch self {
    case let .group(group):
      return .group(group.map { $0.toL2Element() })
    case let .text(text):
      return .text(text, nil)
    case let .input(element, handler):
      switch element.toL2Element() {
      case let .text(text, .none):
        return .text(text, handler)
      default:
        fatalError("Bindings on Groups not aloud right now")
      }
    }
  }
}
