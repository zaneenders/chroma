extension Color: PrimitiveBlock {
  public var focusRule: FocusRule { .standard }
  public var expandsHorizontally: Bool { true }
  public var expandsVertically: Bool { true }

  public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }

  public func register(in rect: Rect, context: BlockContext) {}

  public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    drawList.fillRect(rect, color: self)
  }
}
