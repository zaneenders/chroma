@MainActor
struct StackLayout {
  enum Axis {
    case horizontal, vertical

    var main: WritableKeyPath<Size, Float> { self == .horizontal ? \.width : \.height }
    var cross: WritableKeyPath<Size, Float> { self == .horizontal ? \.height : \.width }
  }

  var axis: Axis
  var spacing: Float
  var bottomAligned = false

  private func layout(
    _ children: [BlockEngine.Resolved], spacers: [Bool], proposal: Size
  ) -> [Size] {
    var sizes = children.map { $0.sizeThatFits(proposal) }
    for index in sizes.indices where spacers[index] {
      sizes[index][keyPath: axis.cross] = 0
    }
    let expands = children.map { axis == .horizontal ? $0.expandsHorizontally : $0.expandsVertically }
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
        var childProposal = proposal
        childProposal[keyPath: axis.main] = share
        sizes[index] = children[index].sizeThatFits(childProposal)
        sizes[index][keyPath: axis.main] = share
        if spacers[index] { sizes[index][keyPath: axis.cross] = 0 }
      }
    }
    return sizes
  }

  func measure(_ children: [any Block], proposal: Size, context: BlockContext) -> Size {
    prepare(children, reversed: false, context: context).sizeThatFits(proposal)
  }

  func draw(
    _ originals: [any Block], reversed: Bool, into drawList: inout DrawList,
    in rect: Rect, context: BlockContext
  ) {
    prepare(originals, reversed: reversed, context: context).draw(into: &drawList, in: rect)
  }

  func prepare(_ originals: [any Block], reversed: Bool, context: BlockContext) -> BlockEngine.Resolved {
    let children = originals.enumerated().map { index, child in
      BlockEngine.resolve(child, context: context.childContext(for: child, at: index))
    }
    let spacers = originals.map(BlockEngine.isSpacer)
    return BlockEngine.Resolved(
      expandsHorizontally: {
        children.indices.contains { (axis == .horizontal || !spacers[$0]) && children[$0].expandsHorizontally }
      },
      expandsVertically: {
        children.indices.contains { (axis == .vertical || !spacers[$0]) && children[$0].expandsVertically }
      },
      measure: { proposal in
        guard !children.isEmpty else { return .zero }
        let sizes = layout(children, spacers: spacers, proposal: proposal)
        var result = Size.zero
        result[keyPath: axis.main] = sizes.reduce(0) { $0 + $1[keyPath: axis.main] } + spacing * Float(sizes.count - 1)
        result[keyPath: axis.cross] = sizes.map { $0[keyPath: axis.cross] }.max() ?? 0
        return result
      },
      draw: { list, rect in
        let sizes = layout(children, spacers: spacers, proposal: rect.size)
        place(children, sizes: sizes, reversed: reversed, into: &list, in: rect, context: context)
      })
  }

  private func place(
    _ children: [BlockEngine.Resolved], sizes: [Size], reversed: Bool,
    into drawList: inout DrawList, in rect: Rect, context: BlockContext
  ) {
    let interaction = context.interaction
    interaction.beginGroup(
      rect: rect, axis: axis == .horizontal ? .horizontal : .vertical)
    var cursor = axis == .horizontal ? rect.minX : rect.minY
    if reversed { cursor += rect.size[keyPath: axis.main] }
    for (child, size) in zip(children, sizes) {
      let extent = size[keyPath: axis.main]
      if reversed { cursor -= extent }
      let origin =
        axis == .horizontal
        ? Point(x: cursor, y: bottomAligned ? rect.maxY - size.height : rect.minY)
        : Point(x: rect.minX, y: cursor)
      child.draw(into: &drawList, in: Rect(origin: origin, size: size))
      cursor += reversed ? -spacing : extent + spacing
    }
    interaction.endGroup()
  }
}
