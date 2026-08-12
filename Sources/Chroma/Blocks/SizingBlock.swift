public struct SizingBlock: PrimitiveBlock {
  public var content: any Block
  public var x: Sizing
  public var y: Sizing

  @MainActor public var expandsHorizontally: Bool { x == .grow }
  @MainActor public var expandsVertically: Bool { y == .grow }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    let childSize = BlockEngine.measure(
      content,
      proposal: Size(
        width: proposedSize(for: x, available: proposal.width),
        height: proposedSize(for: y, available: proposal.height)
      ),
      context: context
    )
    return Size(
      width: resolvedSize(for: x, available: proposal.width, fitted: childSize.width),
      height: resolvedSize(for: y, available: proposal.height, fitted: childSize.height)
    )
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
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
