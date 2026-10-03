public struct ZStack: LayoutPreparingBlock {
  var scopedChildren: [any Block]

  public var children: [any Block] {
    scopedChildren.map { ($0 as? ScopedBlock)?.content ?? $0 }
  }

  public init(@BlockBuilder content: () -> TupleBlock) {
    self.scopedChildren = BlockBuilder.flattenedChildren(content().scopedChildren)
  }

}
