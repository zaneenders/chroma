@MainActor
public enum BlockEngine {
  /// Owned by one traversal. Expansion, measurement, and painting share the same body values.
  /// Proposal-dependent sizes are discarded with the tree, so the next traversal observes fresh state.
  @MainActor final class Resolved {
    init(
      expandsHorizontally: @escaping () -> Bool,
      expandsVertically: @escaping () -> Bool,
      measure: @escaping (Size) -> Size,
      draw: @escaping (inout DrawList, Rect) -> Void
    ) {
      horizontalExpansion = expandsHorizontally
      verticalExpansion = expandsVertically
      self.measure = measure
      self.paint = draw
    }

    convenience init(
      child: Resolved,
      draw: @escaping (inout DrawList, Rect) -> Void
    ) {
      self.init(
        expandsHorizontally: { child.expandsHorizontally },
        expandsVertically: { child.expandsVertically },
        measure: child.sizeThatFits,
        draw: draw)
    }

    private let horizontalExpansion: () -> Bool
    private let verticalExpansion: () -> Bool
    private let measure: (Size) -> Size
    private let paint: (inout DrawList, Rect) -> Void
    private var measurements: [(proposal: Size, size: Size)] = []

    lazy var expandsHorizontally = horizontalExpansion()
    lazy var expandsVertically = verticalExpansion()

    func sizeThatFits(_ proposal: Size) -> Size {
      if let cached = measurements.first(where: { $0.proposal == proposal }) { return cached.size }
      let size = measure(proposal)
      measurements.append((proposal, size))
      return size
    }

    func draw(into drawList: inout DrawList, in rect: Rect) {
      paint(&drawList, rect)
    }
  }

  static func resolve(_ block: any Block, context: BlockContext) -> Resolved {
    if let scoped = block as? ScopedBlock {
      return resolve(scoped.content, context: context.scoped(scoped.path))
    }
    if let primitive = block as? any PrimitiveBlock {
      let context =
        primitive.preservesContentIdentity
        ? context : context.scoped([.component(ObjectIdentifier(type(of: block)))])
      if let container = primitive as? any LayoutPreparingBlock {
        return container.prepareLayout(context: context)
      }
      return Resolved(
        expandsHorizontally: { primitive.expandsHorizontally },
        expandsVertically: { primitive.expandsVertically },
        measure: { primitive.sizeThatFits($0, context: context) },
        draw: { list, rect in drawResolved(primitive, into: &list, in: rect, context: context) })
    }
    return resolve(block.body, context: context.scoped([.component(ObjectIdentifier(type(of: block)))]))
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
