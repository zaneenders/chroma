public struct TupleBlock: Block {
  public private(set) var children: [any Block]
  var branch: Int?
  public init(children: [any Block]) { self.children = children }

  @MainActor func emitChildren(into buffer: inout LayoutBuffer, context: BlockContext) -> [LayoutNode] {
    let context = branch.map { context.scoped([.branch($0)]) } ?? context
    return children.enumerated().map { index, child in
      buffer.emit(child, context: context.childScope(index))
    }
  }
  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    let children = emitChildren(into: &buffer, context: context)
    return buffer.fragment(children, context: context)
  }
}
