public struct Interactive<Content: Block>: PaintableBlock {
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

  @MainActor public func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    var childContext = context
    childContext.focusTargets = []
    childContext.focusLeafClaimed = true
    BlockEngine.paintRegistered(into: &drawList, in: rect, context: childContext)
  }
}

extension Interactive: LayoutPreparingBlock {
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    // Layout queries intentionally use the idle tree. The current-phase tree belongs
    // to this operation and is shared by registration and painting, never a later event.
    let idle = BlockEngine.resolve(content(.idle), context: context)
    var childContext = context
    childContext.focusTargets = []
    childContext.focusLeafClaimed = true
    var active: BlockEngine.Resolved?
    var activePhase: InteractionPhase?
    func current(_ phase: InteractionPhase) -> BlockEngine.Resolved {
      if let active, activePhase == phase { return active }
      let resolved = BlockEngine.resolve(content(phase), context: childContext)
      active = resolved
      activePhase = phase
      return resolved
    }
    let id = id ?? context.widgetID
    return BlockEngine.Resolved(
      expandsHorizontally: { idle.expandsHorizontally },
      expandsVertically: { idle.expandsVertically },
      measure: idle.sizeThatFits,
      register: { rect in
        let state = context.buttonState(id: id, in: rect, action: action)
        current(state.phase).register(in: rect)
      },
      paint: { list, rect in
        // Canonical update has prepared this exact phase; direct standalone paint may
        // prepare a fresh visual tree, but never installs its handlers or focus leaves.
        let child = active ?? current(context.buttonVisualState(id: id).phase)
        child.paint(into: &list, in: rect)
      },
      draw: { list, rect in
        let state = context.buttonState(id: id, in: rect, action: action)
        current(state.phase).draw(into: &list, in: rect)
      })
  }
}
