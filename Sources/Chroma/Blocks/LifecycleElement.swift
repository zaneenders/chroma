public protocol LifecycleElement: PrimitiveBlock {
  @MainActor func prepareInteraction(in rect: Rect, context: BlockContext)
  @MainActor func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext)
  @MainActor func visualBounds(in rect: Rect, context: BlockContext) -> Rect?
}

@MainActor
extension LifecycleElement {
  public func prepareInteraction(in rect: Rect, context: BlockContext) {}
  public func visualBounds(in rect: Rect, context: BlockContext) -> Rect? { nil }

  public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    prepareInteraction(in: rect, context: context)
    paint(into: &drawList, in: rect, context: context)
  }
}
