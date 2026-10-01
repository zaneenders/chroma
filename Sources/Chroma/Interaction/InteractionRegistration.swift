@MainActor
extension Interaction {
  struct ScopedCommandHandler {
    var path: [Int]
    var command: Command
    var action: @MainActor () -> CommandResult
  }
  struct ScopedKeyBindings {
    var path: [Int]
    var bindings: KeyBindings
  }
  struct ScopedActionRole {
    var path: [Int]
    var role: ActionRole
    var action: @MainActor () -> Void
  }

  struct FrameRegistrations {
    var commandHandlers: [ScopedCommandHandler] = []
    var keyBindingScopes: [ScopedKeyBindings] = []
    var actionRoles: [ScopedActionRole] = []
    var inputHandlers: [WidgetID: @MainActor () -> Void] = [:]
    var buttonActions: [WidgetID: @MainActor () -> Void] = [:]
    var focusTargets: [ObjectIdentifier: (target: FocusTarget, id: WidgetID)] = [:]
  }

  func beginGroup(
    rect: Rect,
    axis: FocusNode.Axis? = nil,
    scrollID: WidgetID? = nil,
    navigationID: WidgetID? = nil,
    navigationName: String? = nil
  ) {
    guard let parent = builderStack.last else {
      preconditionFailure("beginGroup outside of a frame; call beginFrame first")
    }
    let node = FocusNode(
      kind: .group, rect: rect, hitRect: clippedRect(rect), axis: axis, scrollID: scrollID,
      navigationID: navigationID, navigationName: navigationName,
      canBeRevealed: scrollID != nil || (builderStack.last?.canBeRevealed ?? false))
    let capacity = EngineDiagnostics.enabled ? parent.children.capacity : 0
    defer {
      if EngineDiagnostics.enabled && parent.children.capacity != capacity {
        EngineDiagnostics.focusArrayCapacityGrowth += 1
      }
    }
    parent.children.append(node)
    builderPath.append(parent.children.count - 1)
    builderStack.append(node)
  }

  @discardableResult
  func endGroup() -> Bool {
    guard builderStack.count > 1, let node = builderStack.popLast() else {
      preconditionFailure("endGroup without a matching beginGroup")
    }
    builderPath.removeLast()
    if node.children.isEmpty {
      builderStack.last?.children.removeLast()
      return false
    }
    return true
  }

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
    action: (@MainActor () -> Void)? = nil, navigationIgnored: Bool = false
  ) -> ButtonState {
    guard let parent = builderStack.last else {
      preconditionFailure("interactiveBehavior outside of a frame; call beginFrame first")
    }
    let capacity = EngineDiagnostics.enabled ? parent.children.capacity : 0
    defer {
      if EngineDiagnostics.enabled && parent.children.capacity != capacity {
        EngineDiagnostics.focusArrayCapacityGrowth += 1
      }
    }
    parent.children.append(
      FocusNode(
        kind: .leaf(id), rect: rect, hitRect: clippedRect(rect), role: role,
        canBeRevealed: parent.canBeRevealed, navigationIgnored: navigationIgnored))
    if role != .normal, let action {
      building.actionRoles.append(ScopedActionRole(path: builderPath, role: role, action: action))
    }

    let focused = selectedLeafID == id
    let hovered = hoveredLeafID == id
    let held = pressedLeaf == id && input.pointerDown
    if let action { building.buttonActions[id] = action }
    return ButtonState(hovered: hovered, focused: focused, held: held, clicked: activatedLeaf == id)
  }

  func clippedRect(_ rect: Rect) -> Rect {
    guard let clip = clipStack.last else { return rect }
    return rect.intersection(clip) ?? .zero
  }
}
