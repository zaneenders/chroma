public struct DeferredBlock<Content: Block>: Block {
  private let content: @MainActor () -> Content

  public init(@BlockBuilder content: @escaping @MainActor () -> Content) {
    self.content = content
  }

  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    PipelineMetrics.record(.bodyEvaluation)
    return buffer.emit(content(), context: context.component(Self.self))
  }
}
