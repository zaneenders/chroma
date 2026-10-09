public struct Spacer: Block {
  public init() {}
  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    buffer.spacer(context: context)
  }
}
