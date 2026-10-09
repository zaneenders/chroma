public struct VStack: Block {
  public var spacing: Float
  var content: TupleBlock
  public var children: [any Block] { content.children }
  public var isLayoutReversed = false

  public init(
    spacing: Float = 0,
    @BlockBuilder content: () -> TupleBlock
  ) {
    self.spacing = spacing
    self.content = content()
  }

  public func reverseLayout() -> VStack {
    var copy = self
    copy.isLayoutReversed.toggle()
    return copy
  }

  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    let children = content.emitChildren(into: &buffer, context: context)
    return buffer.stack(children, axis: .vertical, spacing: spacing, reversed: isLayoutReversed, context: context)
  }
}
