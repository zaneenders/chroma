public struct ZStack: Block {
  var content: TupleBlock
  public var children: [any Block] { content.children }

  public init(@BlockBuilder content: () -> TupleBlock) {
    self.content = content()
  }

  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    let children = content.emitChildren(into: &buffer, context: context)
    return buffer.overlay(children, context: context)
  }
}
