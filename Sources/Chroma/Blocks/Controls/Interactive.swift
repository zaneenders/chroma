public struct Interactive<Content: Block>: LayoutPreparingBlock {
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

}

extension Interactive {
  @MainActor public func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    // Layout queries intentionally use the idle tree. The current-phase tree belongs
    // to this operation and is shared by registration and painting, never a later event.
    var idle: BlockEngine.Resolved?
    func measurementTree() -> BlockEngine.Resolved {
      if let idle { return idle }
      let resolved = BlockEngine.resolve(content(.idle), context: context)
      idle = resolved
      return resolved
    }
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
      expandsHorizontally: { measurementTree().expandsHorizontally },
      expandsVertically: { measurementTree().expandsVertically },
      measure: { measurementTree().sizeThatFits($0) },
      register: { rect in
        let state = context.buttonState(id: id, in: rect, action: action)
        current(state.phase).register(in: rect)
      },
      paint: { list, rect in
        // Canonical update has prepared this exact phase; direct standalone paint may
        // prepare a fresh visual tree, but never installs its handlers or focus leaves.
        let child = active ?? current(context.buttonVisualState(id: id).phase)
        child.paint(into: &list, in: rect)
      })
  }
}
