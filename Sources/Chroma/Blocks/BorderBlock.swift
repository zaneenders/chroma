public struct BorderBlock: PrimitiveBlock {
  public var content: any Block
  public var color: Color
  public var radii: CornerRadii = .zero
  public var width: Float

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
    if radii == .zero {
      drawList.strokeRect(rect, width: width, color: color)
    } else {
      drawList.strokeRoundedRect(rect, radii: radii, width: width, color: color)
    }
  }
}

public typealias RoundedBorderBlock = BorderBlock
