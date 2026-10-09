/// A keyed scalar transition whose sampled value is shared by layout, input and drawing.
/// Keep its structural identity stable to preserve progress across reordering.
/// Removing or virtualizing the block cancels its transition.
public struct AnimatedValue<Content: Block>: Block {
  public let target: Float
  public let duration: Double
  private let content: @MainActor (Float) -> Content

  public init(
    _ target: Float, duration: Double = 0.2,
    @BlockBuilder content: @escaping @MainActor (Float) -> Content
  ) {
    precondition(target.isFinite && duration.isFinite && duration >= 0)
    self.target = target
    self.duration = duration
    self.content = content
  }

  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    let context = context.component(Self.self)
    let state = context.interaction.animation(context.widgetID, target: target, duration: duration)
    let child = buffer.emit(content(state.value(at: context.interaction.animationTime)), context: context)
    return buffer.node(.animation(child, state), context: context)
  }
}
