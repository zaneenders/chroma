/// Optional authoring syntax. Direct construction uses the same buffer methods.
public protocol Block {
  @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode
}

extension String: Block {
  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    buffer.text(Text(self), context: context)
  }
}

/// A root construction function; no Block value or result builder is required.
public typealias LayoutBuilder = @MainActor (inout LayoutBuffer, BlockContext) -> LayoutNode
