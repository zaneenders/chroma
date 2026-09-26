public struct ZStack: PrimitiveBlock {
  var scopedChildren: [any Block]

  public var children: [any Block] {
    scopedChildren.map { ($0 as? ScopedBlock)?.content ?? $0 }
  }

  public init(@BlockBuilder content: () -> TupleBlock) {
    self.scopedChildren = BlockBuilder.flattenedChildren(content().scopedChildren)
  }

  public var focusRule: FocusRule { .container }

  @MainActor public var expandsHorizontally: Bool {
    scopedChildren.contains { BlockEngine.expandsHorizontally($0) }
  }

  @MainActor public var expandsVertically: Bool {
    scopedChildren.contains { BlockEngine.expandsVertically($0) }
  }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    var result = Size.zero
    for (index, child) in scopedChildren.enumerated() {
      let context = context.childContext(for: child, at: index)
      let size = BlockEngine.measure(child, proposal: proposal, context: context)
      result.width = max(result.width, size.width)
      result.height = max(result.height, size.height)
    }
    return result
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let interaction = context.interaction
    interaction.beginGroup(rect: rect)
    for (index, child) in scopedChildren.enumerated() {
      let context = context.childContext(for: child, at: index)
      let size = BlockEngine.measure(child, proposal: rect.size, context: context)
      BlockEngine.draw(
        child,
        into: &drawList,
        in: Rect(x: rect.minX, y: rect.minY, width: size.width, height: size.height),
        context: context)
    }
    interaction.endGroup()
  }
}
