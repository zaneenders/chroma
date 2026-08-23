public struct BackgroundBlock: PrimitiveBlock {
  public var content: any Block
  public var background: any Block

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    BlockEngine.draw(background, into: &drawList, in: rect, context: context)
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
  }
}
