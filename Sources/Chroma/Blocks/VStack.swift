public struct VStack: PrimitiveBlock {
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

  public func reverseLayout() -> VStack {
    var copy = self
    copy.isLayoutReversed.toggle()
    return copy
  }

  @MainActor public var expandsHorizontally: Bool {
    children.contains { child in
      !(child is Spacer) && BlockEngine.expandsHorizontally(child)
    }
  }

  @MainActor public var expandsVertically: Bool {
    children.contains { BlockEngine.expandsVertically($0) }
  }

  @MainActor private func layout(children: [any PrimitiveBlock], proposal: Size, context: RenderContext) -> [Size] {
    var sizes = children.map { $0.sizeThatFits(proposal, context: context) }
    for index in sizes.indices where self.children[index] is Spacer {
      sizes[index].width = 0
    }
    var fixedTotal: Float = 0
    var expanderCount = 0
    let expands = children.map { $0.expandsVertically }
    for (index, size) in sizes.enumerated() {
      if expands[index] {
        expanderCount += 1
      } else {
        fixedTotal += size.height
      }
    }
    if expanderCount > 0 {
      let spacingTotal = spacing * Float(max(0, children.count - 1))
      let share = max(0, proposal.height - fixedTotal - spacingTotal) / Float(expanderCount)
      for index in sizes.indices where expands[index] {
        sizes[index].height = share
      }
    }
    return sizes
  }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    guard !children.isEmpty else { return .zero }
    let sizes = layout(children: children.map { BlockEngine.resolve($0) }, proposal: proposal, context: context)
    let height = sizes.reduce(0) { $0 + $1.height } + spacing * Float(sizes.count - 1)
    let width = sizes.map(\.width).max() ?? 0
    return Size(width: width, height: height)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let children = children.map { BlockEngine.resolve($0) }
    let sizes = layout(children: children, proposal: rect.size, context: context)
    let interaction = context.interaction
    interaction.beginGroup(.vertical, rect: rect)
    let cursorOnGroup = interaction.isCurrentGroupSelected
    var y = isLayoutReversed ? rect.maxY : rect.minY
    for (child, size) in zip(children, sizes) {
      let width = size.width
      let x = rect.minX
      if isLayoutReversed {
        y -= size.height
      }
      child.draw(
        into: &drawList, in: Rect(x: x, y: y, width: width, height: size.height), context: context)
      y += isLayoutReversed ? -spacing : size.height + spacing
    }
    let retainedFocusGroup = interaction.endGroup()
    if cursorOnGroup && retainedFocusGroup {
      drawList.strokeRect(rect, width: 1, color: interaction.groupCursorColor)
    }
  }
}
