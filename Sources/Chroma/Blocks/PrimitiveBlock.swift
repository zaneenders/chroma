/// How a primitive joins the focus tree and paints hover state. Every primitive declares
/// one; the engine reads the declaration instead of inferring interactivity from what the
/// primitive happens to register while drawing.
public enum FocusRule: Sendable {
  /// The engine registers the primitive's whole rect as one focus leaf and paints the
  /// standard highlight for it — the rule for plain visible content.
  case standard
  /// The primitive registers exactly one focus leaf while drawing and paints its own
  /// hover, focus, and press feedback. Drawing fails if it registers none.
  case control
  /// The primitive draws its own focus structure — nested blocks, rows, or cells — and
  /// the engine registers nothing for the primitive itself.
  case container
  /// The primitive never joins the focus tree.
  case decorative
}

public protocol PrimitiveBlock: Block where Body == Never {
  var focusRule: FocusRule { get }

  @MainActor func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size

  @MainActor func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext)

  @MainActor var expandsHorizontally: Bool { get }

  @MainActor var expandsVertically: Bool { get }
}

extension PrimitiveBlock {
  public var body: Never { fatalError("\(Self.self) is a primitive block") }
  public var expandsHorizontally: Bool { false }
  public var expandsVertically: Bool { false }
}
