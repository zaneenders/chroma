public struct EmptyBlock: Block {
  public init() {}
  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    buffer.empty(context: context)
  }
}
