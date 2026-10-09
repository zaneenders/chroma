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
  @MainActor public func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
    // Layout queries intentionally use the idle tree. The current-phase tree belongs
    // to this operation and is shared by registration and painting, never a later event.
    var idle: LayoutNode?
    func measurementTree(_ buffer: inout LayoutBuffer) -> LayoutNode {
      if let idle { return idle }
      let resolved = buffer.prepare(content(.idle), context: context)
      idle = resolved
      return resolved
    }
    var childContext = context
    childContext.focusTargets = []
    childContext.focusLeafClaimed = true
    var active: LayoutNode?
    var activePhase: InteractionPhase?
    func current(_ phase: InteractionPhase, buffer: inout LayoutBuffer) -> LayoutNode {
      if let active, activePhase == phase { return active }
      let resolved = buffer.prepare(content(phase), context: childContext)
      active = resolved
      activePhase = phase
      return resolved
    }
    let id = id ?? context.widgetID
    return buffer.append(
      expandsHorizontally: { buffer in
        let child = measurementTree(&buffer)
        return buffer.expandsHorizontally(child)
      },
      expandsVertically: { buffer in
        let child = measurementTree(&buffer)
        return buffer.expandsVertically(child)
      },
      measure: { buffer, proposal in
        let child = measurementTree(&buffer)
        return buffer.sizeThatFits(child, proposal)
      },
      register: { buffer, rect in
        let state = context.buttonState(id: id, in: rect, action: action)
        let child = current(state.phase, buffer: &buffer)
        buffer.register(child, in: rect)
      },
      paint: { buffer, list, rect in
        // Canonical update has prepared this exact phase; direct standalone paint may
        // prepare a fresh visual tree, but never installs its handlers or focus leaves.
        let child = active ?? current(context.buttonVisualState(id: id).phase, buffer: &buffer)
        buffer.paint(child, into: &list, in: rect)
      })
  }
}
