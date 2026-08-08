@MainActor
extension Interaction {
  func pushClip(_ rect: Rect) {
    let clip = clipStack.last.flatMap { $0.intersection(rect) } ?? (clipStack.isEmpty ? rect : .zero)
    clipStack.append(clip)
  }

  func popClip() {
    guard !clipStack.isEmpty else {
      preconditionFailure("popClip without a matching pushClip")
    }
    clipStack.removeLast()
  }

  func interactiveBehavior(
    id: WidgetID, rect: Rect, role: ActionRole = .normal,
    action: (@MainActor () -> Void)? = nil
  ) -> ButtonState {
    guard let parent = builderStack.last else {
      preconditionFailure("interactiveBehavior outside of a frame; call beginFrame first")
    }
    parent.children.append(FocusNode(kind: .leaf(id), rect: clippedRect(rect), role: role))
    if role != .normal, let action { actionRoles[role] = action }

    let selected = selectedLeafID == id
    let held = pressedLeaf == id && input.pointerDown
    var clicked = false
    if selected && activatePending {
      clicked = true
      activatePending = false
      requestRedraw()
    }
    return ButtonState(hovered: selected, held: held, clicked: clicked)
  }

  func clippedRect(_ rect: Rect) -> Rect {
    guard let clip = clipStack.last else { return rect }
    return rect.intersection(clip) ?? .zero
  }

}

public enum InteractionPhase: Equatable, Sendable {
  case idle
  case hovered
  case pressed
}

public struct ButtonState: Equatable, Sendable {
  public var hovered: Bool
  public var held: Bool
  public var clicked: Bool

  public init(hovered: Bool, held: Bool, clicked: Bool) {
    self.hovered = hovered
    self.held = held
    self.clicked = clicked
  }

  public var phase: InteractionPhase {
    held ? .pressed : hovered ? .hovered : .idle
  }
}

public struct TextInputState: Equatable, Sendable {
  public var hovered: Bool
  public var held: Bool
  public var editing: Bool
  public var caretOffset: Int?

  public init(hovered: Bool, held: Bool, editing: Bool, caretOffset: Int?) {
    self.hovered = hovered
    self.held = held
    self.editing = editing
    self.caretOffset = caretOffset
  }

  public var phase: InteractionPhase {
    held ? .pressed : hovered ? .hovered : .idle
  }
}
