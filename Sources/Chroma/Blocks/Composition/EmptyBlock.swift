public struct EmptyBlock: PaintableBlock {
  public init() {}
  public var focusRule: FocusRule { .decorative }
  public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { .zero }
  public func register(in rect: Rect, context: BlockContext) {}

  public func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    draw(into: &drawList, in: rect, context: context)
  }

  public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {}
}
