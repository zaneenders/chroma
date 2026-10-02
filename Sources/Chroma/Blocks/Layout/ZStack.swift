public struct ZStack: PrimitiveBlock {
  var scopedChildren: [any Block]

  public var children: [any Block] {
    scopedChildren.map { ($0 as? ScopedBlock)?.content ?? $0 }
  }

  public init(@BlockBuilder content: () -> TupleBlock) {
    self.scopedChildren = BlockBuilder.flattenedChildren(content().scopedChildren)
  }

  public var focusRule: FocusRule { .container }

  @MainActor public var expandsHorizontally: Bool {
    scopedChildren.contains { BlockEngine.expandsHorizontally($0) }
  }

  @MainActor public var expandsVertically: Bool {
    scopedChildren.contains { BlockEngine.expandsVertically($0) }
  }

  @MainActor public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    prepareLayout(context: context).sizeThatFits(proposal)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    prepareLayout(context: context).draw(into: &drawList, in: rect)
  }
}
