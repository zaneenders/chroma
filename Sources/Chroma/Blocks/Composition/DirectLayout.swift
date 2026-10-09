/// Construct the same layout records as Block builders, without building an intermediate tree.
/// Prepare each child with its own context (`childScope` or `keyed`) to preserve its state.
public struct DirectLayout: LayoutPreparingBlock {
  private let content: @MainActor (inout LayoutBuffer, BlockContext) -> LayoutNode

  public init(_ content: @escaping @MainActor (inout LayoutBuffer, BlockContext) -> LayoutNode) {
    self.content = content
  }

  @MainActor public func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
    content(&buffer, context)
  }
}
