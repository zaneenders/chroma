public struct HStack: PrimitiveBlock {
  public var spacing: Float
  var scopedChildren: [any Block]

  public var children: [any Block] {
    get { scopedChildren.map { ($0 as? ScopedBlock)?.content ?? $0 } }
    set { scopedChildren = newValue }
  }
  public var isLayoutReversed = false

  public init(
    spacing: Float = 0,
    @BlockBuilder content: () -> TupleBlock
  ) {
    self.spacing = spacing
    self.scopedChildren = BlockBuilder.flattenedChildren(content().scopedChildren)
  }

  public func reverseLayout() -> HStack {
    var copy = self
    copy.isLayoutReversed.toggle()
    return copy
  }

  @MainActor public var expandsHorizontally: Bool {
    scopedChildren.contains { BlockEngine.expandsHorizontally($0) }
  }

  @MainActor public var expandsVertically: Bool {
    scopedChildren.contains { child in
      !BlockEngine.isSpacer(child) && BlockEngine.expandsVertically(child)
    }
  }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    StackLayout(axis: .horizontal, spacing: spacing).measure(scopedChildren, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    StackLayout(axis: .horizontal, spacing: spacing).draw(
      scopedChildren, reversed: isLayoutReversed, into: &drawList, in: rect, context: context)
  }
}
