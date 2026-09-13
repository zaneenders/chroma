public struct DeferredBlock<Content: Block>: Block {
  private let content: @MainActor () -> Content

  public init(@BlockBuilder content: @escaping @MainActor () -> Content) {
    self.content = content
  }

  @MainActor public var body: Content { content() }
}
