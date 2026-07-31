public struct Interactive<Content: Block>: PrimitiveBlock {
  public var id: WidgetID
  public var action: () -> Void
  public var content: (InteractionPhase) -> Content

  public init(
    id: WidgetID,
    action: @escaping () -> Void,
    content: @escaping (InteractionPhase) -> Content
  ) {
    self.id = id
    self.action = action
    self.content = content
  }

  public init(
    id: String,
    action: @escaping () -> Void,
    content: @escaping (InteractionPhase) -> Content
  ) {
    self.init(id: WidgetID(id), action: action, content: content)
  }


  @MainActor public var expandsHorizontally: Bool {
    BlockEngine.expandsHorizontally(content(.idle))
  }

  @MainActor public var expandsVertically: Bool {
    BlockEngine.expandsVertically(content(.idle))
  }

  @MainActor public func sizeThatFits(_ proposal: Size) -> Size {
    BlockEngine.measure(content(.idle), proposal: proposal)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect) {
    let state = Interaction.current.interactiveBehavior(id: id, rect: rect)
    if state.clicked { action() }
    BlockEngine.draw(content(state.phase), into: &drawList, in: rect)
  }
}
