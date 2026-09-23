public struct FocusScopeBlock: PrimitiveBlock, IdentityTransparentBlock {
  public var content: any Block

  public init(content: any Block) {
    self.content = content
  }

  public var focusRule: FocusRule { .container }

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let interaction = context.interaction
    interaction.beginGroup(rect: rect, scopeID: context.widgetID)
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
    interaction.endGroup()
    if interaction.isFocusInside(scopeID: context.widgetID) {
      drawList.strokeRoundedRect(rect, radius: 6, width: 1, color: context.theme.focus.ring)
    }
  }
}

extension Block {
  /// Marks this subtree as a focus scope: a boundary that `stepIn`/`stepOut` navigation
  /// (bound to `s`/`l` in the vim preset) moves across.
  ///
  /// A scope behaves as one unit from the outside — `stepOut` leaves it for the nearest
  /// control beyond its edge in a single step, and `stepIn` returns to the control last
  /// focused inside it instead of always the first. Scroll containers are scopes
  /// automatically, so long virtualized lists can be entered and left without walking
  /// to their edges.
  public func focusScope() -> some Block {
    FocusScopeBlock(content: self)
  }
}
