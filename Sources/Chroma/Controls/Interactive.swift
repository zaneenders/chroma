/// Each visual phase is lowered once within the current buffer operation. The
/// idle child used for measurement is also the child registered in the idle phase.
@MainActor
struct InteractiveNode {
  let id: WidgetID
  let action: @MainActor () -> Void
  let content: @MainActor (inout LayoutBuffer, LayoutContext, InteractionPhase) -> LayoutNode
  let context: LayoutContext
  private var idle: LayoutNode?
  private var hovered: LayoutNode?
  private var pressed: LayoutNode?
  private var active: LayoutNode?

  init(
    id: WidgetID?, action: @escaping @MainActor () -> Void,
    content: @escaping @MainActor (inout LayoutBuffer, LayoutContext, InteractionPhase) -> LayoutNode,
    context: LayoutContext
  ) {
    self.id = id ?? context.widgetID
    self.action = action
    self.content = content
    self.context = context
  }

  mutating func child(for phase: InteractionPhase, in buffer: inout LayoutBuffer) -> LayoutNode {
    let existing: LayoutNode?
    switch phase {
    case .idle: existing = idle
    case .hovered: existing = hovered
    case .pressed: existing = pressed
    }
    if let existing { return existing }
    var childContext = context
    childContext.focusTargets = []
    childContext.focusLeafClaimed = true
    let child = content(&buffer, childContext, phase)
    switch phase {
    case .idle: idle = child
    case .hovered: hovered = child
    case .pressed: pressed = child
    }
    return child
  }

  mutating func expandsHorizontally(in buffer: inout LayoutBuffer) -> Bool {
    let child = child(for: .idle, in: &buffer)
    return buffer.expandsHorizontally(child)
  }

  mutating func expandsVertically(in buffer: inout LayoutBuffer) -> Bool {
    let child = child(for: .idle, in: &buffer)
    return buffer.expandsVertically(child)
  }

  mutating func sizeThatFits(_ proposal: Size, in buffer: inout LayoutBuffer) -> Size {
    let child = child(for: .idle, in: &buffer)
    return buffer.sizeThatFits(child, proposal)
  }

  mutating func register(in rect: Rect, buffer: inout LayoutBuffer) {
    let state = context.buttonState(id: id, in: rect, action: action)
    let child = child(for: state.phase, in: &buffer)
    active = child
    buffer.register(child, in: rect)
  }

  func paint(into list: inout DrawList, in rect: Rect, buffer: inout LayoutBuffer) {
    guard let active else { preconditionFailure("Interactive painting requires preceding registration") }
    buffer.paint(active, into: &list, in: rect)
  }
}
