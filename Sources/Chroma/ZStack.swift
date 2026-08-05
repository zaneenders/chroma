public struct ZStack: PrimitiveBlock {
  public var alignment: Alignment
  public var children: [any Block]

  public init(alignment: Alignment = .center, @BlockBuilder content: () -> TupleBlock) {
    self.alignment = alignment
    self.children = BlockBuilder.flattenedChildren(content().children)
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
    let interaction = context.interaction
    interaction.beginGroup(.none, rect: rect)
    let cursorOnGroup = interaction.isCurrentGroupSelected
    for child in children {
      let size = BlockEngine.measure(child, proposal: rect.size, context: context)
      BlockEngine.draw(child, into: &drawList, in: rect.placing(size, alignment: alignment), context: context)
    }
    interaction.endGroup()
    if cursorOnGroup {
      drawList.strokeRect(rect, width: 1, color: interaction.groupCursorColor)
    }
  }
}
