struct LayoutModifier: PrimitiveBlock, IdentityTransparentBlock {
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
    switch operation {
    case .padding(let insets):
      let childSize = BlockEngine.measure(
        content,
        proposal: Size(
          width: max(0, proposal.width - insets.leading - insets.trailing),
          height: max(0, proposal.height - insets.top - insets.bottom)
        ), context: context)
      return Size(
        width: childSize.width + insets.leading + insets.trailing,
        height: childSize.height + insets.top + insets.bottom
      )
    case .sizing(let x, let y):
      let childSize = BlockEngine.measure(
        content,
        proposal: Size(
          width: proposedSize(for: x, available: proposal.width),
          height: proposedSize(for: y, available: proposal.height)
        ), context: context)
      return Size(
        width: resolvedSize(for: x, available: proposal.width, fitted: childSize.width),
        height: resolvedSize(for: y, available: proposal.height, fitted: childSize.height)
      )
    }
  }

  @MainActor func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    switch operation {
    case .padding(let insets):
      BlockEngine.draw(
        content, into: &drawList,
        in: Rect(
          x: rect.minX + insets.leading,
          y: rect.minY + insets.top,
          width: rect.size.width - insets.leading - insets.trailing,
          height: rect.size.height - insets.top - insets.bottom
        ), context: context)
    case .sizing:
      BlockEngine.draw(content, into: &drawList, in: rect, context: context)
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
