/// Modified
public typealias Selected = Bool
public typealias InputHandler = (Selected, AsciiKeyCode) -> Void

extension String {
  @MainActor
  public func bind(handler: @escaping InputHandler) -> some Block {
    Input(wrapped: self, handler: handler)
  }
}

@MainActor
protocol InputBlock: Block {
  var handler: InputHandler { get }
  var wrapped: String { get }
}

struct Input: InputBlock {
  let wrapped: String
  let handler: InputHandler
  var layer: some Block {
    wrapped.layer
  }
}
