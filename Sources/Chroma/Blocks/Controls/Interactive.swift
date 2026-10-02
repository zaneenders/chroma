public struct Interactive<Content: Block>: PrimitiveBlock {
  var id: WidgetID?
  public var action: @MainActor () -> Void
  public var content: @MainActor (InteractionPhase) -> Content

  init(
    id: WidgetID?,
    action: @escaping @MainActor () -> Void,
    content: @escaping @MainActor (InteractionPhase) -> Content
  ) {
    self.id = id
    self.action = action
    self.content = content
  }

  public init(
    action: @escaping @MainActor () -> Void,
    content: @escaping @MainActor (InteractionPhase) -> Content
  ) {
    self.init(id: nil, action: action, content: content)
  }

  init(
    id: String,
    action: @escaping @MainActor () -> Void,
    content: @escaping @MainActor (InteractionPhase) -> Content
  ) {
    self.init(id: WidgetID(id), action: action, content: content)
  }

  public var focusRule: FocusRule { .control }

  @MainActor public var expandsHorizontally: Bool {
    BlockEngine.expandsHorizontally(content(.idle))
  }

  @MainActor public var expandsVertically: Bool {
    BlockEngine.expandsVertically(content(.idle))
  }

  @MainActor public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    BlockEngine.measure(content(.idle), proposal: proposal, context: context)
  }

  @MainActor private func registeredContent(
    in rect: Rect, context: BlockContext
  ) -> (content: Content, context: BlockContext) {
    let id = id ?? context.widgetID
    let state = context.buttonState(id: id, in: rect, action: action)
    var context = context
    context.focusTargets = []
    context.focusLeafClaimed = true
    return (content(state.phase), context)
  }

  @MainActor public func register(in rect: Rect, context: BlockContext) {
    let registered = registeredContent(in: rect, context: context)
    BlockEngine.register(registered.content, in: rect, context: registered.context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    let registered = registeredContent(in: rect, context: context)
    BlockEngine.draw(registered.content, into: &drawList, in: rect, context: registered.context)
  }
}
