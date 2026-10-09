private enum GroupIdentity {}

/// Typed layout and behavior constructors.
/// Child factories receive their final identity and focus context before emission.
extension LayoutBuffer {
  public mutating func padding(_ child: LayoutNode, _ insets: EdgeInsets, context: LayoutContext) -> LayoutNode {
    precondition(contains(child), "Stale layout handle")
    return node(.layout(child, .padding(insets)), context: context)
  }

  public mutating func padding(_ child: LayoutNode, _ amount: Float, context: LayoutContext) -> LayoutNode {
    padding(child, EdgeInsets(amount), context: context)
  }

  public mutating func sizing(
    _ child: LayoutNode, x: Sizing = .fit, y: Sizing = .fit, context: LayoutContext
  ) -> LayoutNode {
    precondition(contains(child), "Stale layout handle")
    return node(.layout(child, .sizing(x: x, y: y)), context: context)
  }

  public mutating func clip(_ child: LayoutNode, context: LayoutContext) -> LayoutNode {
    precondition(contains(child), "Stale layout handle")
    return node(.decoration(child, .clip), context: context)
  }

  public mutating func roundedBackground(
    _ child: LayoutNode, color: Color, radii: CornerRadii, context: LayoutContext
  ) -> LayoutNode {
    precondition(contains(child), "Stale layout handle")
    return node(.decoration(child, .rounded(color, radii)), context: context)
  }

  public mutating func border(
    _ child: LayoutNode, color: Color, radii: CornerRadii = .zero, width: Float = 1, context: LayoutContext
  ) -> LayoutNode {
    precondition(contains(child), "Stale layout handle")
    return node(.decoration(child, .border(color, radii, width)), context: context)
  }

  public mutating func background(
    context: LayoutContext, content: LayoutBuilder, background: LayoutBuilder
  ) -> LayoutNode {
    let child = content(&self, context.backgroundContentContext)
    let background = background(&self, context.backgroundContext)
    return node(.decoration(child, .background(background)), context: context)
  }

  public mutating func group(
    _ name: String? = nil, context: LayoutContext, content: LayoutBuilder
  ) -> LayoutNode {
    let context = context.component(GroupIdentity.self)
    let child = content(&self, context)
    return node(.group(child, name), context: context)
  }

  public mutating func keyBindings(
    _ child: LayoutNode, _ bindings: KeyBindings, context: LayoutContext
  ) -> LayoutNode {
    precondition(contains(child), "Stale layout handle")
    return node(.command(child, .keyBindings(bindings)), context: context)
  }

  public mutating func onCommand(
    _ child: LayoutNode, _ command: Command, context: LayoutContext,
    action: @escaping @MainActor () -> CommandResult
  ) -> LayoutNode {
    precondition(contains(child), "Stale layout handle")
    return node(.command(child, .handler(command, action)), context: context)
  }

  public mutating func focus(
    _ target: FocusTarget, context: LayoutContext, content: LayoutBuilder
  ) -> LayoutNode {
    var context = context
    context.focusTargets.append(target)
    return content(&self, context)
  }

  public mutating func animatedValue(
    _ target: Float, duration: Double = 0.2, context: LayoutContext,
    content: @MainActor (inout LayoutBuffer, LayoutContext, Float) -> LayoutNode
  ) -> LayoutNode {
    precondition(target.isFinite && duration.isFinite && duration >= 0)
    let context = context.component(ScalarAnimation.self)
    let state = context.interaction.animation(context.widgetID, target: target, duration: duration)
    let child = content(&self, context, state.value(at: context.interaction.animationTime))
    return node(.animation(child, state), context: context)
  }

  public mutating func trailingControls(
    spacing: Float, context: LayoutContext, input: LayoutBuilder, controls: LayoutBuilder
  ) -> LayoutNode {
    let input = input(&self, context.childScope(0))
    let controls = controls(&self, context.childScope(1))
    return node(.trailing(input, controls, spacing), context: context)
  }
}
