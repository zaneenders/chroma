public struct NavigationIgnoredBlock: PrimitiveBlock, IdentityTransparentBlock {
  public var content: any Block
  public var focusRule: FocusRule { .container }

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    var context = context
    context.navigationIgnored = true
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
  }
}

extension Block {
  public func navigationIgnored() -> NavigationIgnoredBlock {
    NavigationIgnoredBlock(content: self)
  }
}
