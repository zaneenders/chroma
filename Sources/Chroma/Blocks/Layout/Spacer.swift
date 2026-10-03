public struct Spacer: PaintableBlock {
  public init() {}

  public var focusRule: FocusRule { .decorative }

  public var expandsHorizontally: Bool { true }
  public var expandsVertically: Bool { true }

  public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
  public func register(in rect: Rect, context: BlockContext) {}

  public func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {}
}
