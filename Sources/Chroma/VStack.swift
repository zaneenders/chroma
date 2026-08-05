public struct VStack: PrimitiveBlock {
  public var spacing: Float
  public var alignment: HorizontalAlignment
  public var children: [any Block]

  public init(
    spacing: Float = 0,
    alignment: HorizontalAlignment = .center,
    @BlockBuilder content: () -> TupleBlock
  ) {
    self.spacing = spacing
    self.alignment = alignment
    self.children = BlockBuilder.flattenedChildren(content().children)
  }

  @MainActor public var expandsHorizontally: Bool {
    children.contains { child in
      !(child is Spacer) && BlockEngine.expandsHorizontally(child)
    }
  }

  @MainActor public var expandsVertically: Bool {
    children.contains { BlockEngine.expandsVertically($0) }
  }

  @MainActor private func layout(proposal: Size, context: RenderContext) -> [Size] {
    var sizes = children.map { BlockEngine.measure($0, proposal: proposal, context: context) }
    for index in sizes.indices where children[index] is Spacer {
      sizes[index].width = 0
    }
    var fixedTotal: Float = 0
    var expanderCount = 0
    for (child, size) in zip(children, sizes) {
      if BlockEngine.expandsVertically(child) {
        expanderCount += 1
      } else {
        fixedTotal += size.height
      }
    }
    if expanderCount > 0 {
      let spacingTotal = spacing * Float(max(0, children.count - 1))
      let share = max(0, proposal.height - fixedTotal - spacingTotal) / Float(expanderCount)
      for index in sizes.indices where BlockEngine.expandsVertically(children[index]) {
        sizes[index].height = share
      }
    }
    return sizes
  }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    guard !children.isEmpty else { return .zero }
    let sizes = layout(proposal: proposal, context: context)
    let height = sizes.reduce(0) { $0 + $1.height } + spacing * Float(sizes.count - 1)
    let width = sizes.map(\.width).max() ?? 0
    return Size(width: width, height: height)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let sizes = layout(proposal: rect.size, context: context)
    let interaction = context.interaction
    interaction.beginGroup(.vertical, rect: rect)
    let cursorOnGroup = interaction.isCurrentGroupSelected
    var y = rect.minY
    for (child, size) in zip(children, sizes) {
      let width = min(size.width, rect.size.width)
      let x: Float
      switch alignment {
      case .leading: x = rect.minX
      case .center: x = rect.minX + (rect.size.width - width) / 2
      case .trailing: x = rect.maxX - width
      }
      BlockEngine.draw(child, into: &drawList, in: Rect(x: x, y: y, width: width, height: size.height), context: context)
      y += size.height + spacing
    }
    interaction.endGroup()
    if cursorOnGroup {
      drawList.strokeRect(rect, width: 1, color: interaction.groupCursorColor)
    }
  }
}
