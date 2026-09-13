public struct HStack: PrimitiveBlock {
  public var spacing: Float
  public var children: [any Block]
  public var isLayoutReversed = false

  public init(
    spacing: Float = 0,
    @BlockBuilder content: () -> TupleBlock
  ) {
    self.spacing = spacing
    self.children = BlockBuilder.flattenedChildren(content().children)
  }

  public func reverseLayout() -> HStack {
    var copy = self
    copy.isLayoutReversed.toggle()
    return copy
  }

  @MainActor public var expandsHorizontally: Bool {
    children.contains { BlockEngine.expandsHorizontally($0) }
  }

  @MainActor public var expandsVertically: Bool {
    children.contains { child in
      !(child is Spacer) && BlockEngine.expandsVertically(child)
    }
  }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    StackLayout(axis: .horizontal, spacing: spacing).measure(children, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    StackLayout(axis: .horizontal, spacing: spacing).draw(
      children, reversed: isLayoutReversed, into: &drawList, in: rect, context: context)
  }
}
