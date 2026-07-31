public protocol Block {
  associatedtype Body: Block

  @MainActor var body: Body { get }
}

extension Never: Block {
  public var body: Never { fatalError("Never") }
}

public protocol PrimitiveBlock: Block where Body == Never {
  @MainActor func sizeThatFits(_ proposal: Size) -> Size

  @MainActor func draw(into drawList: inout DrawList, in rect: Rect)

  @MainActor var expandsHorizontally: Bool { get }

  @MainActor var expandsVertically: Bool { get }
}

extension PrimitiveBlock {
  public var body: Never { fatalError("\(Self.self) is a primitive block") }
  public var expandsHorizontally: Bool { false }
  public var expandsVertically: Bool { false }
}

public struct TupleBlock: PrimitiveBlock {
  public var children: [any Block]

  public init(children: [any Block]) {
    self.children = children
  }

  @MainActor public var expandsHorizontally: Bool {
    children.contains { BlockEngine.expandsHorizontally($0) }
  }

  @MainActor public var expandsVertically: Bool {
    children.contains { BlockEngine.expandsVertically($0) }
  }

  @MainActor public func sizeThatFits(_ proposal: Size) -> Size {
    var result = Size.zero
    for child in children {
      let size = BlockEngine.measure(child, proposal: proposal)
      result.width = max(result.width, size.width)
      result.height = max(result.height, size.height)
    }
    return result
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect) {
    for child in children {
      BlockEngine.draw(child, into: &drawList, in: rect)
    }
  }
}
