public struct UpdateBoundary: PrimitiveBlock {
  let content: @MainActor () -> any Block

  @MainActor public init<Content: Block>(@BlockBuilder content: @escaping @MainActor () -> Content) {
    self.content = content
  }

  public var focusRule: FocusRule { .container }
  public var preservesContentIdentity: Bool { true }

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content()) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content()) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    BlockEngine.measure(content(), proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    BlockEngine.draw(content(), into: &drawList, in: rect, context: context)
  }
}
