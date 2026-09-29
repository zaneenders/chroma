@MainActor
public enum BlockEngine {
  @MainActor final class Resolved {
    init(primitive: any PrimitiveBlock, context: BlockContext, child: Resolved?) {
      self.primitive = primitive
      self.context = context
      self.child = child
    }
    let primitive: any PrimitiveBlock
    let context: BlockContext
    let child: Resolved?

    var expandsHorizontally: Bool {
      if let layout = primitive as? LayoutModifier {
        if case .sizing(let x, _) = layout.operation { return x == .grow }
      }
      if let child { return child.expandsHorizontally }
      return primitive.expandsHorizontally
    }

    var expandsVertically: Bool {
      if let layout = primitive as? LayoutModifier {
        if case .sizing(_, let y) = layout.operation { return y == .grow }
      }
      if let child { return child.expandsVertically }
      return primitive.expandsVertically
    }

    func sizeThatFits(_ proposal: Size) -> Size {
      guard let child else { return primitive.sizeThatFits(proposal, context: context) }
      if let layout = primitive as? LayoutModifier {
        return layout.sizeThatFits(proposal, context: context) { proposal in child.sizeThatFits(proposal) }
      }
      return child.sizeThatFits(proposal)
    }

    func draw(into drawList: inout DrawList, in rect: Rect) {
      guard let child else {
        BlockEngine.drawResolved(primitive, into: &drawList, in: rect, context: context)
        return
      }
      if let layout = primitive as? LayoutModifier {
        layout.draw(into: &drawList, in: rect, context: context) { list, rect, _ in
          child.draw(into: &list, in: rect)
        }
      } else if let paint = primitive as? PaintModifier {
        paint.draw(into: &drawList, in: rect, context: context) { list, rect, _ in
          child.draw(into: &list, in: rect)
        }
      } else if let modifier = primitive as? ContextModifier {
        modifier.draw(into: &drawList, in: rect, context: context) { list, rect, modified in
          child.withContext(modified).draw(into: &list, in: rect)
        }
      } else if let scope = primitive as? CommandScope {
        scope.draw(into: &drawList, in: rect, context: context) { list, rect, _ in
          child.draw(into: &list, in: rect)
        }
      }
    }

    func withContext(_ context: BlockContext) -> Resolved {
      var updated = self.context
      updated.hoverStyle = context.hoverStyle
      updated.navigationIgnored = context.navigationIgnored
      return Resolved(primitive: primitive, context: updated, child: child?.withContext(context))
    }
  }

  static func resolve(_ block: any Block, context: BlockContext) -> Resolved {
    if let scoped = block as? ScopedBlock {
      return resolve(scoped.content, context: context.scoped(scoped.path))
    }
    let context = block is any IdentityTransparentBlock
      ? context : context.scoped([.component(ObjectIdentifier(type(of: block)))])
    if let primitive = block as? any PrimitiveBlock {
      var content: (any Block)?
      if let layout = primitive as? LayoutModifier { content = layout.content }
      if let paint = primitive as? PaintModifier { content = paint.content }
      if let modifier = primitive as? ContextModifier { content = modifier.content }
      if let scope = primitive as? CommandScope { content = scope.content }
      if let content {
        let childContext: BlockContext
        if let paint = primitive as? PaintModifier, case .background = paint.operation {
          childContext = context.backgroundContentContext
        } else {
          childContext = context
        }
        return Resolved(primitive: primitive, context: context,
                        child: resolve(content, context: childContext))
      }
      return Resolved(primitive: primitive, context: context, child: nil)
    }
    return resolve(block.body, context: context)
  }

  static func isSpacer(_ block: any Block) -> Bool {
    if let scoped = block as? ScopedBlock { return isSpacer(scoped.content) }
    return block is Spacer
  }

  public static func measure(
    _ block: any Block,
    proposal: Size,
    context: BlockContext
  ) -> Size {
    let resolved = resolve(block, context: context)
    return resolved.sizeThatFits(proposal)
  }

  public static func draw(
    _ block: any Block,
    into drawList: inout DrawList,
    in rect: Rect,
    context: BlockContext
  ) {
    let resolved = resolve(block, context: context)
    resolved.draw(into: &drawList, in: rect)
  }

  static func drawResolved(
    _ primitive: any PrimitiveBlock,
    into drawList: inout DrawList,
    in rect: Rect,
    context: BlockContext
  ) {
    let parent = context.interaction.builderStack.last
    let registered = parent?.children.count
    primitive.draw(into: &drawList, in: rect, context: context)
    guard let parent, parent.children.count == registered else { return }
    switch primitive.focusRule {
    case .control:
      preconditionFailure(
        "\(String(describing: type(of: primitive))) declares focusRule .control but registered no focus leaf; "
          + "call buttonState while drawing")
    case .standard:
      guard !context.focusLeafClaimed, !context.navigationIgnored else { return }
      context.focusable(in: rect, into: &drawList)
    case .container, .decorative:
      break
    }
  }

  static func drawHighlight(
    for id: WidgetID,
    into drawList: inout DrawList,
    in rect: Rect,
    context: BlockContext
  ) {
    let leafState = context.interaction.untrackedLeafState
    let pressed = leafState.pressed == id && context.interaction.input.pointerDown
    guard leafState.selected == id || leafState.hovered == id || pressed else { return }
    if context.hoverStyle == HoverStyle.none { return }
    if leafState.selected == id && !pressed && context.hoverStyle == nil {
      drawList.strokeRect(rect, width: 2, color: context.theme.focus.ring)
      return
    }
    switch context.hoverStyle ?? .standard {
    case .none:
      return
    case .tint(let color):
      drawList.fillRect(rect, color: color)
    case .standard:
      drawList.fillRect(rect, color: HoverStyle.standardTint(in: context.theme, pressed: pressed))
    }
  }

  public static func expandsHorizontally(_ block: any Block) -> Bool {
    resolve(block, context: BlockContext()).expandsHorizontally
  }

  public static func expandsVertically(_ block: any Block) -> Bool {
    resolve(block, context: BlockContext()).expandsVertically
  }
}
