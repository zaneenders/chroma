public enum HStackAlignment: Sendable {
  case top, bottom
}

public struct HStack: LayoutPreparingBlock {
  public var spacing: Float
  public var alignment: HStackAlignment
  var scopedChildren: [any Block]

  public var children: [any Block] {
    scopedChildren.map { ($0 as? ScopedBlock)?.content ?? $0 }
  }
  public var isLayoutReversed = false

  public init(
    spacing: Float = 0,
    alignment: HStackAlignment = .top,
    @BlockBuilder content: () -> TupleBlock
  ) {
    self.spacing = spacing
    self.alignment = alignment
    self.scopedChildren = BlockBuilder.flattenedChildren(content().scopedChildren)
  }

  public func reverseLayout() -> HStack {
    var copy = self
    copy.isLayoutReversed.toggle()
    return copy
  }

}
