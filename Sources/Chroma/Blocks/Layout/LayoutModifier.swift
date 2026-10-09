struct LayoutModifier: Block {
  enum Operation {
    case padding(EdgeInsets)
    case sizing(x: Sizing, y: Sizing)
  }

  var content: any Block
  var operation: Operation

  @MainActor func sizeThatFits(
    _ proposal: Size, context: BlockContext, measure: (Size) -> Size
  ) -> Size {
    switch operation {
    case .padding(let insets):
      let childSize = measure(
        Size(
          width: max(0, proposal.width - insets.leading - insets.trailing),
          height: max(0, proposal.height - insets.top - insets.bottom)
        ))
      return Size(
        width: childSize.width + insets.leading + insets.trailing,
        height: childSize.height + insets.top + insets.bottom
      )
    case .sizing(let x, let y):
      let childSize = measure(
        Size(
          width: proposedSize(for: x, available: proposal.width),
          height: proposedSize(for: y, available: proposal.height)
        ))
      return Size(
        width: resolvedSize(for: x, available: proposal.width, fitted: childSize.width),
        height: resolvedSize(for: y, available: proposal.height, fitted: childSize.height)
      )
    }
  }

  static func placed(_ operation: Operation, in rect: Rect) -> Rect {
    switch operation {
    case .padding(let insets):
      Rect(
        x: rect.minX + insets.leading, y: rect.minY + insets.top,
        width: rect.size.width - insets.leading - insets.trailing,
        height: rect.size.height - insets.top - insets.bottom)
    case .sizing: rect
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
