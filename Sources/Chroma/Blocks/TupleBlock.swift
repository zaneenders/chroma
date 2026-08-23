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

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    var result = Size.zero
    for child in children {
      let size = BlockEngine.measure(child, proposal: proposal, context: context)
      result.width = max(result.width, size.width)
      result.height = max(result.height, size.height)
    }
    return result
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    for child in children {
      BlockEngine.draw(child, into: &drawList, in: rect, context: context)
    }
  }
}
