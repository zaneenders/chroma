public struct HStack: PrimitiveBlock {
  public var spacing: Float
  public var alignment: VerticalAlignment
  public var children: [any Block]

  public init(
    spacing: Float = 0,
    alignment: VerticalAlignment = .center,
    @BlockBuilder content: () -> TupleBlock
  ) {
    self.spacing = spacing
    self.alignment = alignment
    self.children = BlockBuilder.flattenedChildren(content().children)
  }

  @MainActor public var expandsHorizontally: Bool {
    children.contains { BlockEngine.expandsHorizontally($0) }
  }

  @MainActor public var expandsVertically: Bool {
    children.contains { child in
      !(child is Spacer) && BlockEngine.expandsVertically(child)
    }
  }

  @MainActor private func layout(proposal: Size, context: RenderContext) -> [Size] {
    var sizes = children.map { BlockEngine.measure($0, proposal: proposal, context: context) }
    for index in sizes.indices where children[index] is Spacer {
      sizes[index].height = 0
    }
    var fixedTotal: Float = 0
    var expanderCount = 0
    for (child, size) in zip(children, sizes) {
      if BlockEngine.expandsHorizontally(child) {
        expanderCount += 1
      } else {
        fixedTotal += size.width
      }
    }
    if expanderCount > 0 {
      let spacingTotal = spacing * Float(max(0, children.count - 1))
      let share = max(0, proposal.width - fixedTotal - spacingTotal) / Float(expanderCount)
      for index in sizes.indices where BlockEngine.expandsHorizontally(children[index]) {
        sizes[index].width = share
      }
    }
    return sizes
  }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    guard !children.isEmpty else { return .zero }
    let sizes = layout(proposal: proposal, context: context)
    let width = sizes.reduce(0) { $0 + $1.width } + spacing * Float(sizes.count - 1)
    let height = sizes.map(\.height).max() ?? 0
    return Size(width: width, height: height)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let sizes = layout(proposal: rect.size, context: context)
    let interaction = context.interaction
    interaction.beginGroup(.horizontal, rect: rect)
    let cursorOnGroup = interaction.isCurrentGroupSelected
    var x = rect.minX
    for (child, size) in zip(children, sizes) {
      let height = min(size.height, rect.size.height)
      let y: Float
      switch alignment {
      case .top: y = rect.minY
      case .center: y = rect.minY + (rect.size.height - height) / 2
      case .bottom: y = rect.maxY - height
      }
      BlockEngine.draw(child, into: &drawList, in: Rect(x: x, y: y, width: size.width, height: height), context: context)
      x += size.width + spacing
    }
    interaction.endGroup()
    if cursorOnGroup {
      drawList.strokeRect(rect, width: 1, color: interaction.groupCursorColor)
    }
  }
}
