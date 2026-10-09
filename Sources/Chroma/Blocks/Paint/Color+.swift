extension Color: Block {
  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    buffer.color(self, context: context)
  }

  var focusRule: FocusRule { .standard }
  var expandsHorizontally: Bool { true }
  var expandsVertically: Bool { true }

  func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }

  func register(in rect: Rect, context: BlockContext) {}

  func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    drawList.fillRect(rect, color: self)
  }
}
