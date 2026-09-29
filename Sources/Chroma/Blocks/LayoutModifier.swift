struct LayoutModifier: PrimitiveBlock, CollectionDistributingBlock {
  enum Operation {
    case padding(EdgeInsets)
    case sizing(x: Sizing, y: Sizing)
  }

  var content: any Block
  var operation: Operation

  var focusRule: FocusRule { .container }

  @MainActor var expandsHorizontally: Bool {
    switch operation {
    case .padding: BlockEngine.expandsHorizontally(content)
    case .sizing(let x, _): x == .grow
    }
  }

  @MainActor var expandsVertically: Bool {
    switch operation {
    case .padding: BlockEngine.expandsVertically(content)
    case .sizing(_, let y): y == .grow
    }
  }

  @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    sizeThatFits(proposal, context: context) { proposal in
      BlockEngine.measure(content, proposal: proposal, context: context)
    }
  }

  @MainActor func sizeThatFits(
    _ proposal: Size, context: BlockContext, measure: (Size) -> Size
  ) -> Size {
    switch operation {
    case .padding(let insets):
      let childSize = measure(Size(
        width: max(0, proposal.width - insets.leading - insets.trailing),
        height: max(0, proposal.height - insets.top - insets.bottom)
      ))
      return Size(
        width: childSize.width + insets.leading + insets.trailing,
        height: childSize.height + insets.top + insets.bottom
      )
    case .sizing(let x, let y):
      let childSize = measure(Size(
        width: proposedSize(for: x, available: proposal.width),
        height: proposedSize(for: y, available: proposal.height)
      ))
      return Size(
        width: resolvedSize(for: x, available: proposal.width, fitted: childSize.width),
        height: resolvedSize(for: y, available: proposal.height, fitted: childSize.height)
      )
    }
  }

  @MainActor func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    draw(into: &drawList, in: rect, context: context) { list, rect, context in
      BlockEngine.draw(content, into: &list, in: rect, context: context)
    }
  }

  @MainActor func draw(
    into drawList: inout DrawList, in rect: Rect, context: BlockContext,
    drawContent: (inout DrawList, Rect, BlockContext) -> Void
  ) {
    switch operation {
    case .padding(let insets):
      drawContent(
        &drawList, Rect(
          x: rect.minX + insets.leading,
          y: rect.minY + insets.top,
          width: rect.size.width - insets.leading - insets.trailing,
        height: rect.size.height - insets.top - insets.bottom
        ), context)
    case .sizing:
      drawContent(&drawList, rect, context)
    }
  }

  private func proposedSize(for sizing: Sizing, available: Float) -> Float {
    switch sizing {
    case .fit, .grow: available
    case .fixed(let size): size
    }
  }

  private func resolvedSize(for sizing: Sizing, available: Float, fitted: Float) -> Float {
    switch sizing {
    case .fit: fitted
    case .fixed(let size): size
    case .grow: available
    }
  }
}
