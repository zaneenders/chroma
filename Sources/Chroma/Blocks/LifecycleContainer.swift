public protocol LifecycleContainer: PrimitiveBlock {
  @MainActor func lifecycleContent(context: BlockContext) -> any Block
  @MainActor func handleInput(in rect: Rect, context: BlockContext)
  @MainActor func willPlace(in rect: Rect, context: BlockContext)
  @MainActor func prepareChildren(in rect: Rect, context: BlockContext, prepare: () -> Void)
  @MainActor func paintChildren(in rect: Rect, context: BlockContext, paint: () -> Void)
}

@MainActor
extension LifecycleContainer {
  nonisolated public var focusRule: FocusRule { .container }
  public func handleInput(in rect: Rect, context: BlockContext) {}
  public func willPlace(in rect: Rect, context: BlockContext) {}
  public func prepareChildren(in rect: Rect, context: BlockContext, prepare: () -> Void) { prepare() }
  public func paintChildren(in rect: Rect, context: BlockContext, paint: () -> Void) { paint() }
  public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    BlockEngine.measure(lifecycleContent(context: context), proposal: proposal, context: context)
  }
  public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    willPlace(in: rect, context: context)
    prepareChildren(in: rect, context: context) {}
    paintChildren(in: rect, context: context) {
      BlockEngine.draw(lifecycleContent(context: context), into: &drawList, in: rect, context: context)
    }
  }
}
