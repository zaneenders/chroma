@MainActor
public enum BlockEngine {
  static func resolve(_ block: any Block) -> any PrimitiveBlock {
    if let scoped = block as? ScopedBlock { return resolve(scoped.content) }
    if let primitive = block as? any PrimitiveBlock { return primitive }
    return resolve(block.body)
  }

  static func resolve(
    _ block: any Block, context: RenderContext
  ) -> (primitive: any PrimitiveBlock, context: RenderContext) {
    if let scoped = block as? ScopedBlock {
      return resolve(scoped.content, context: context.scoped(scoped.path))
    }
    let context =
      block is any IdentityTransparentBlock
      ? context : context.scoped([.component(ObjectIdentifier(type(of: block)))])
    if let primitive = block as? any PrimitiveBlock { return (primitive, context) }
    return resolve(block.body, context: context)
  }

  static func isSpacer(_ block: any Block) -> Bool {
    if let scoped = block as? ScopedBlock { return isSpacer(scoped.content) }
    return block is Spacer
  }

  public static func measure(
    _ block: any Block,
    proposal: Size,
    context: RenderContext
  ) -> Size {
    let resolved = resolve(block, context: context)
    return resolved.primitive.sizeThatFits(proposal, context: resolved.context)
  }

  public static func draw(
    _ block: any Block,
    into drawList: inout DrawList,
    in rect: Rect,
    context: RenderContext
  ) {
    let resolved = resolve(block, context: context)
    drawResolved(resolved.primitive, into: &drawList, in: rect, context: resolved.context)
  }

  /// Draws a resolved primitive. A `.standard` primitive that draws without registering a
  /// focus node becomes the default focus leaf itself: the engine registers its rect and
  /// paints the standard highlight, so keyboard focus and pointer hover reach every
  /// visible element — text, images, custom content — and both draw the same highlight.
  /// `.control` primitives must register their own leaf while drawing; `.container`
  /// primitives own their focus structure; `.decorative` primitives never join the tree.
  /// Content a registered leaf already owns (`focusLeafClaimed`) and `.navigationIgnored()`
  /// content never register a default leaf.
  static func drawResolved(
    _ primitive: any PrimitiveBlock,
    into drawList: inout DrawList,
    in rect: Rect,
    context: RenderContext
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
    context: RenderContext
  ) {
    let leafState = context.interaction.untrackedLeafState
    let pressed = leafState.pressed == id && context.interaction.input.pointerDown
    guard leafState.selected == id || leafState.hovered == id || pressed else { return }
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
    resolve(block).expandsHorizontally
  }

  public static func expandsVertically(_ block: any Block) -> Bool {
    resolve(block).expandsVertically
  }
}
