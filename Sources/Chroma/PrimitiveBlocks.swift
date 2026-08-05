extension Color: PrimitiveBlock {
  public var expandsHorizontally: Bool { true }
  public var expandsVertically: Bool { true }

  public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }

  public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    drawList.fillRect(rect, color: self)
  }
}

public struct EmptyBlock: PrimitiveBlock {
  public init() {}
  public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { .zero }
  public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {}
}
