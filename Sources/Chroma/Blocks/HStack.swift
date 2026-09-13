public struct HStack: PrimitiveBlock {
  public var spacing: Float
  public var children: [any Block]
  public var isLayoutReversed = false

  public init(
    spacing: Float = 0,
    @BlockBuilder content: () -> TupleBlock
  ) {
    self.spacing = spacing
    self.children = BlockBuilder.flattenedChildren(content().children)
  }

  public func reverseLayout() -> HStack {
    var copy = self
    copy.isLayoutReversed.toggle()
    return copy
  }

  @MainActor public var expandsHorizontally: Bool {
    children.contains { BlockEngine.expandsHorizontally($0) }
  }

  @MainActor public var expandsVertically: Bool {
    children.contains { child in
      !(child is Spacer) && BlockEngine.expandsVertically(child)
    }
  }

  @MainActor private func layout(children: [any PrimitiveBlock], proposal: Size, context: RenderContext) -> [Size] {
    var sizes = children.map { $0.sizeThatFits(proposal, context: context) }
    for index in sizes.indices where self.children[index] is Spacer {
      sizes[index].height = 0
    }
    var fixedTotal: Float = 0
    var expanderCount = 0
    let expands = children.map { $0.expandsHorizontally }
    for (index, size) in sizes.enumerated() {
      if expands[index] {
        expanderCount += 1
      } else {
        fixedTotal += size.width
      }
    }
    if expanderCount > 0 {
      let spacingTotal = spacing * Float(max(0, children.count - 1))
      let share = max(0, proposal.width - fixedTotal - spacingTotal) / Float(expanderCount)
      for index in sizes.indices where expands[index] {
        sizes[index].width = share
      }
    }
    return sizes
  }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    guard !children.isEmpty else { return .zero }
    let sizes = layout(children: children.map { BlockEngine.resolve($0) }, proposal: proposal, context: context)
    let width = sizes.reduce(0) { $0 + $1.width } + spacing * Float(sizes.count - 1)
    let height = sizes.map(\.height).max() ?? 0
    return Size(width: width, height: height)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let children = children.map { BlockEngine.resolve($0) }
    let sizes = layout(children: children, proposal: rect.size, context: context)
    let interaction = context.interaction
    interaction.beginGroup(.horizontal, rect: rect)
    let cursorOnGroup = interaction.isCurrentGroupSelected
    var x = isLayoutReversed ? rect.maxX : rect.minX
    for (child, size) in zip(children, sizes) {
      let height = size.height
      let y = rect.minY
      if isLayoutReversed {
        x -= size.width
      }
      child.draw(
        into: &drawList, in: Rect(x: x, y: y, width: size.width, height: height), context: context)
      x += isLayoutReversed ? -spacing : size.width + spacing
    }
    let retainedFocusGroup = interaction.endGroup()
    if cursorOnGroup && retainedFocusGroup {
      drawList.strokeRect(rect, width: 1, color: interaction.groupCursorColor)
    }
  }
}
