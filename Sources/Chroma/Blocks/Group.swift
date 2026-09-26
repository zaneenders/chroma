public struct Group: PrimitiveBlock {
  public var name: String?
  public var content: any Block

  public init(_ name: String? = nil, @BlockBuilder content: () -> TupleBlock) {
    self.name = name
    self.content = content()
  }

  public var focusRule: FocusRule { .container }

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    context.interaction.beginGroup(rect: rect, navigationID: context.widgetID, navigationName: name)
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
    context.interaction.endGroup()
  }
}
