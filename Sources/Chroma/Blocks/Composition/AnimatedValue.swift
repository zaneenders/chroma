/// A keyed scalar transition whose sampled value is shared by layout, input and drawing.
/// Keep its structural identity stable to preserve progress across reordering.
/// Removing or virtualizing the block cancels its transition.
public struct AnimatedValue<Content: Block>: LayoutPreparingBlock {
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

  @MainActor public func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
    let state = context.interaction.animation(context.widgetID, target: target, duration: duration)
    let child = buffer.prepare(content(state.value(at: context.interaction.animationTime)), context: context)
    return buffer.append(
      child: child,
      register: { buffer, rect in
        context.interaction.animationKeys.insert(context.widgetID)
        context.interaction.animations[context.widgetID] = state
        buffer.register(child, in: rect)
      },
      paint: { buffer, list, rect in buffer.paint(child, into: &list, in: rect) })
  }
}
