public struct TupleBlock: LayoutPreparingBlock {
  var scopedChildren: [any Block]

  public var children: [any Block] {
    scopedChildren.map { ($0 as? ScopedBlock)?.content ?? $0 }
  }

  public init(children: [any Block]) {
    self.scopedChildren = children
  }

}
