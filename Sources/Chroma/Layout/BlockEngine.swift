@MainActor
public enum BlockEngine {
  /// Owned by one traversal. Expansion, measurement, and painting share the same body values.
  /// Proposal-dependent sizes are discarded with the tree, so the next traversal observes fresh state.
  @MainActor public final class Resolved {
    public init(
      expandsHorizontally: @escaping () -> Bool = { false },
      expandsVertically: @escaping () -> Bool = { false },
      measure: @escaping (Size) -> Size,
      register: @escaping (Rect) -> Void,
      paint: @escaping (inout DrawList, Rect) -> Void,
      draw: ((inout DrawList, Rect) -> Void)? = nil
    ) {
      horizontalExpansion = expandsHorizontally
      verticalExpansion = expandsVertically
      self.measure = measure
      self.update = register
      self.presentation = paint
      self.combined =
        draw ?? { list, rect in
          register(rect)
          paint(&list, rect)
        }
    }

    public convenience init(
      child: Resolved,
      register: @escaping (Rect) -> Void,
      paint: @escaping (inout DrawList, Rect) -> Void,
      draw: ((inout DrawList, Rect) -> Void)? = nil
    ) {
      self.init(
        expandsHorizontally: { child.expandsHorizontally },
        expandsVertically: { child.expandsVertically },
        measure: child.sizeThatFits,
        register: register, paint: paint, draw: draw)
    }

    private let metricsLifetime = PipelineMetrics.trackLifetime(.resolvedNode)
    private let horizontalExpansion: () -> Bool
    private let verticalExpansion: () -> Bool
    private let measure: (Size) -> Size
    private let update: (Rect) -> Void
    private let presentation: (inout DrawList, Rect) -> Void
    private let combined: (inout DrawList, Rect) -> Void
    private var measurements: [(proposal: Size, size: Size)] = []

    public private(set) lazy var expandsHorizontally = horizontalExpansion()
    public private(set) lazy var expandsVertically = verticalExpansion()

    public func sizeThatFits(_ proposal: Size) -> Size {
      PipelineMetrics.record(.measurement)
      if let cached = measurements.first(where: { $0.proposal == proposal }) {
        PipelineMetrics.record(.measurementCacheHit)
        return cached.size
      }
      let size = measure(proposal)
      measurements.append((proposal, size))
      return size
    }

    public func register(in rect: Rect) {
      PipelineMetrics.record(.placement)
      PipelineMetrics.record(.registration)
      update(rect)
    }

    public func draw(into drawList: inout DrawList, in rect: Rect) {
      PipelineMetrics.record(.placement)
      PipelineMetrics.record(.paint)
      BlockEngine.countDrawingCommands(into: &drawList) { list in combined(&list, rect) }
    }
    public func paint(into drawList: inout DrawList, in rect: Rect) {
      PipelineMetrics.record(.paint)
      BlockEngine.countDrawingCommands(into: &drawList) { list in presentation(&list, rect) }
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
      var legacyCommands: DrawList?
      return Resolved(
        expandsHorizontally: { primitive.expandsHorizontally },
        expandsVertically: { primitive.expandsVertically },
        measure: { primitive.sizeThatFits($0, context: context) },
        register: { rect in
          if context.isPresentationUpdate && !(primitive is any PaintableBlock) {
            PipelineMetrics.recordCompatibilityFallback(type(of: primitive))
            PipelineMetrics.record(.paint)
            var commands = DrawList()
            // Legacy drawing is an explicit update adapter, never a presentation effect.
            paintingDepth += 1
            drawResolved(primitive, into: &commands, in: rect, context: context)
            paintingDepth -= 1
            legacyCommands = commands
          } else {
            registerResolved(primitive, in: rect, context: context)
          }
        },
        paint: { list, rect in
          if let legacyCommands {
            list.append(legacyCommands)
          } else {
            paintResolved(primitive, into: &list, in: rect, context: context)
          }
        },
        draw: { list, rect in drawResolved(primitive, into: &list, in: rect, context: context) })
    }
    PipelineMetrics.record(.bodyEvaluation)
    return resolve(block.body, context: context.scoped([.component(ObjectIdentifier(type(of: block)))]))
  }

  private static var paintingDepth = 0

  /// Count once at the outermost drawing boundary, including nested legacy adapters.
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
    let resolved = resolve(block, context: context)
    return resolved.sizeThatFits(proposal)
  }

  public static func draw(
    _ block: any Block,
    into drawList: inout DrawList,
    in rect: Rect,
    context: BlockContext
  ) {
    var context = context
    context.isPresentationUpdate = true
    let resolved = resolve(block, context: context)
    resolved.draw(into: &drawList, in: rect)
  }

  /// Builds one consistent interaction update from fresh block values. The resolved tree and
  /// proposal caches live only for this call; identity alone never retains callbacks or layout.
  public static func register(_ block: any Block, in rect: Rect, context: BlockContext) {
    let resolved = resolve(block, context: context)
    resolved.register(in: rect)
  }

  /// Prepares fresh child values once for a custom primitive's current operation.
  /// Keep the result local to `prepareLayout`; never retain it across updates.
  public static func prepare(_ block: any Block, context: BlockContext) -> Resolved {
    resolve(block, context: context)
  }

  static func paintResolved(
    _ primitive: any PrimitiveBlock, into drawList: inout DrawList, in rect: Rect,
    context: BlockContext
  ) {
    guard let primitive = primitive as? any PaintableBlock else {
      preconditionFailure("Unmigrated primitives require the explicit legacy presentation path")
    }
    primitive.paint(into: &drawList, in: rect, context: context)
    if primitive.focusRule == .standard, !context.focusLeafClaimed, !context.navigationIgnored {
      drawHighlight(for: context.widgetID, into: &drawList, in: rect, context: context)
    }
  }

  static func registerResolved(_ primitive: any PrimitiveBlock, in rect: Rect, context: BlockContext) {
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
