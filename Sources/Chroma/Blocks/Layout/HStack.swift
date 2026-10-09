public enum HStackAlignment: Sendable {
  case top, bottom
}

public struct HStack: Block {
  public var spacing: Float
  public var alignment: HStackAlignment
  var content: TupleBlock
  public var children: [any Block] { content.children }
  public var isLayoutReversed = false

  public init(
    spacing: Float = 0,
    alignment: HStackAlignment = .top,
    @BlockBuilder content: () -> TupleBlock
  ) {
    self.spacing = spacing
    self.alignment = alignment
    self.content = content()
  }

  public func reverseLayout() -> HStack {
    var copy = self
    copy.isLayoutReversed.toggle()
    return copy
  }

  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    let children = content.emitChildren(into: &buffer, context: context)
    return buffer.stack(
      children, axis: .horizontal, spacing: spacing, reversed: isLayoutReversed, bottomAligned: alignment == .bottom,
      context: context)
  }
}
