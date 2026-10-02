public enum FocusRule: Sendable {
  case standard
  case control
  case container
  case decorative
}

public protocol PrimitiveBlock: Block where Body == Never {
  var focusRule: FocusRule { get }
  var preservesContentIdentity: Bool { get }

  /// Measures without changing application or interaction state. Identical proposals may reuse
  /// the result within a traversal; drawing must not depend on how often measurement was called.
  @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size

  /// Reconciles current input behavior and geometry without painting. The default adapter
  /// preserves source compatibility for custom primitives by drawing into a temporary list;
  /// override this method to remove that explicitly instrumented compatibility work.
  @MainActor func register(in rect: Rect, context: BlockContext)

  @MainActor func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext)

  @MainActor var expandsHorizontally: Bool { get }

  @MainActor var expandsVertically: Bool { get }
}

extension PrimitiveBlock {
  public var preservesContentIdentity: Bool { false }
  public var body: Never { fatalError("\(Self.self) is a primitive block") }
  public var expandsHorizontally: Bool { false }
  public var expandsVertically: Bool { false }
}

extension PrimitiveBlock {
  @MainActor public func register(in rect: Rect, context: BlockContext) {
    if let prepared = self as? any LayoutPreparingBlock {
      prepared.prepareLayout(context: context).register(in: rect)
      return
    }
    // Legacy custom primitives may install commands, focus, or editing callbacks in draw.
    // Do not silently skip them based on focusRule, which does not describe those effects.
    PipelineMetrics.recordCompatibilityFallback(Self.self)
    PipelineMetrics.record(.paint)
    var discarded = DrawList()
    BlockEngine.countDrawingCommands(into: &discarded) { list in
      draw(into: &list, in: rect, context: context)
    }
  }
}

/// A primitive whose presentation only emits commands from its current update.
/// Implement registration/input effects in `register`, never in `paint`.
public protocol PaintableBlock: PrimitiveBlock {
  @MainActor func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext)
}
