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
