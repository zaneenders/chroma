@MainActor
public enum BlockEngine {
  private static var paintingDepth = 0

  /// Count once at the outermost drawing boundary, including nested prepared children.
  static func countDrawingCommands(
    into drawList: inout DrawList, _ body: (inout DrawList) -> Void
  ) {
    guard PipelineMetrics.isEnabled else {
      body(&drawList)
      return
    }
    let outermost = paintingDepth == 0
    let before = drawList.commands.count
    paintingDepth += 1
    body(&drawList)
    paintingDepth -= 1
    if outermost { PipelineMetrics.record(.drawingCommands, count: drawList.commands.count - before) }
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
    var resolved = prepare(block, context: context)
    return resolved.sizeThatFits(proposal)
  }

  /// Builds one consistent interaction update from fresh block values. The resolved tree and
  /// proposal caches live only for this call; identity alone never retains callbacks or layout.
  public static func register(_ block: any Block, in rect: Rect, context: BlockContext) {
    var resolved = prepare(block, context: context)
    resolved.register(in: rect)
  }

  /// Prepares fresh child values once for a custom primitive's current operation.
  /// Keep the result local to `prepareLayout`; never retain it across updates.
  public static func prepare(_ block: any Block, context: BlockContext) -> PreparedLayout {
    var buffer = LayoutBuffer()
    let root = buffer.prepare(block, context: context)
    return PreparedLayout(buffer: consume buffer, root: root)
  }

  static func paintResolved(
    _ primitive: any PaintableBlock, into drawList: inout DrawList, in rect: Rect,
    context: BlockContext
  ) {
    primitive.paint(into: &drawList, in: rect, context: context)
    if primitive.focusRule == .standard, !context.focusLeafClaimed, !context.navigationIgnored {
      drawHighlight(for: context.widgetID, into: &drawList, in: rect, context: context)
    }
  }

  static func registerResolved(_ primitive: any PaintableBlock, in rect: Rect, context: BlockContext) {
    let parent = context.interaction.builderStack.last
    let registered = parent?.children.count
    primitive.register(in: rect, context: context)
    guard let parent, parent.children.count == registered else { return }
    switch primitive.focusRule {
    case .control:
      preconditionFailure(
        "\(String(describing: type(of: primitive))) declares focusRule .control but registered no focus leaf; "
          + "call buttonState while registering")
    case .standard:
      guard !context.focusLeafClaimed, !context.navigationIgnored else { return }
      context.registerFocusable(in: rect)
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
    var prepared = prepare(block, context: BlockContext())
    return prepared.expandsHorizontally
  }

  public static func expandsVertically(_ block: any Block) -> Bool {
    var prepared = prepare(block, context: BlockContext())
    return prepared.expandsVertically
  }
}
