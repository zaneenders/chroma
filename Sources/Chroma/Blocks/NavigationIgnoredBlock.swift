struct NavigationIgnoredBlock: PrimitiveBlock, IdentityTransparentBlock {
  public var content: any Block
  public var focusRule: FocusRule { .container }

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    var context = context
    context.navigationIgnored = true
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
  }
}

extension Button {
  @available(*, unavailable, message: "Buttons must remain navigable.")
  public func navigationIgnored() -> some Block {
    NavigationIgnoredBlock(content: self)
  }
}

extension Block {
  public func navigationIgnored() -> some Block {
    NavigationIgnoredBlock(content: self)
  }
}
