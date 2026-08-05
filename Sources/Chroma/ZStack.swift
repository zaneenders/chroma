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
    let interaction = Interaction.current
    interaction.beginGroup(.none, rect: rect)
    let cursorOnGroup = interaction.isCurrentGroupSelected
    for child in children {
      let size = BlockEngine.measure(child, proposal: rect.size)
      BlockEngine.draw(child, into: &drawList, in: rect.placing(size, alignment: alignment))
    }
    interaction.endGroup()
    if cursorOnGroup {
      drawList.strokeRect(rect, width: 1, color: interaction.groupCursorColor)
    }
  }
}
