public struct EmptyBlock: PrimitiveBlock {
  public init() {}
  public var focusRule: FocusRule { .decorative }
  public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { .zero }
  public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {}
}
