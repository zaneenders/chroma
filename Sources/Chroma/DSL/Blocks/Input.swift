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
  associatedtype Wrapped: Block
  var layer: Wrapped { get }
}

struct Input<W: Block>: InputBlock {
  let wrapped: W
  let handler: InputHandler
  var layer: some Block {
    wrapped.layer
  }
}
