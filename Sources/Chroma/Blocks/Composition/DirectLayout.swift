/// Construct the same layout records as Block builders, without building an intermediate tree.
/// Prepare each child with its own context (`childScope` or `keyed`) to preserve its state.
public struct DirectLayout: Block {
  private let content: @MainActor (inout LayoutBuffer, BlockContext) -> LayoutNode

  public init(_ content: @escaping @MainActor (inout LayoutBuffer, BlockContext) -> LayoutNode) {
    self.content = content
  }

  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    content(&buffer, context)
  }
}
