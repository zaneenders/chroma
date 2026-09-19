@MainActor
struct StackLayout {
  enum Axis {
    case horizontal, vertical

    var main: WritableKeyPath<Size, Float> { self == .horizontal ? \.width : \.height }
    var cross: WritableKeyPath<Size, Float> { self == .horizontal ? \.height : \.width }

    @MainActor func expands(_ child: any PrimitiveBlock) -> Bool {
      self == .horizontal ? child.expandsHorizontally : child.expandsVertically
    }
  }

  var axis: Axis
  var spacing: Float

  private func layout(
    _ children: [(primitive: any PrimitiveBlock, context: RenderContext)], originals: [any Block], proposal: Size,
    context: RenderContext
  ) -> [Size] {
    var sizes = children.map { $0.primitive.sizeThatFits(proposal, context: $0.context) }
    for index in sizes.indices where BlockEngine.isSpacer(originals[index]) {
      sizes[index][keyPath: axis.cross] = 0
    }
    let expands = children.map { axis.expands($0.primitive) }
    var fixedTotal: Float = 0
    var expanderCount = 0
    for (index, size) in sizes.enumerated() {
      if expands[index] {
        expanderCount += 1
      } else {
        fixedTotal += size[keyPath: axis.main]
      }
    }
    if expanderCount > 0 {
      let spacingTotal = spacing * Float(max(0, children.count - 1))
      let share = max(0, proposal[keyPath: axis.main] - fixedTotal - spacingTotal) / Float(expanderCount)
      for index in sizes.indices where expands[index] {
        sizes[index][keyPath: axis.main] = share
      }
    }
    return sizes
  }

  func measure(_ children: [any Block], proposal: Size, context: RenderContext) -> Size {
    guard !children.isEmpty else { return .zero }
    let sizes = layout(
      children.enumerated().map { index, child in
        BlockEngine.resolve(child, context: context.childContext(for: child, at: index))
      }, originals: children, proposal: proposal, context: context)
    var result = Size.zero
    result[keyPath: axis.main] = sizes.reduce(0) { $0 + $1[keyPath: axis.main] } + spacing * Float(sizes.count - 1)
    result[keyPath: axis.cross] = sizes.map { $0[keyPath: axis.cross] }.max() ?? 0
    return result
  }

  func draw(
    _ originals: [any Block], reversed: Bool, into drawList: inout DrawList,
    in rect: Rect, context: RenderContext
  ) {
    let children = originals.enumerated().map { index, child in
      BlockEngine.resolve(child, context: context.childContext(for: child, at: index))
    }
    let sizes = layout(children, originals: originals, proposal: rect.size, context: context)
    let interaction = context.interaction
    interaction.beginGroup(
      rect: rect, axis: axis == .horizontal ? .horizontal : .vertical)
    var cursor = axis == .horizontal ? rect.minX : rect.minY
    if reversed { cursor += rect.size[keyPath: axis.main] }
    for (child, size) in zip(children, sizes) {
      let extent = size[keyPath: axis.main]
      if reversed { cursor -= extent }
      let origin = axis == .horizontal ? Point(x: cursor, y: rect.minY) : Point(x: rect.minX, y: cursor)
      child.primitive.draw(into: &drawList, in: Rect(origin: origin, size: size), context: child.context)
      cursor += reversed ? -spacing : extent + spacing
    }
    interaction.endGroup()
  }
}
