public enum FocusRule: Sendable {
  case standard
  case control
  case container
  case decorative
}

/// A leaf with explicit interaction registration and side-effect-free painting.
public protocol PaintableBlock: Block where Body == Never {
  var focusRule: FocusRule { get }
  var preservesContentIdentity: Bool { get }
  @MainActor var expandsHorizontally: Bool { get }
  @MainActor var expandsVertically: Bool { get }
  @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size
  @MainActor func register(in rect: Rect, context: BlockContext)
  @MainActor func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext)
}

extension PaintableBlock {
  public var preservesContentIdentity: Bool { false }
  public var body: Never { fatalError("\(Self.self) is a paintable block") }
  public var expandsHorizontally: Bool { false }
  public var expandsVertically: Bool { false }

  @MainActor public func draw(into list: inout DrawList, in rect: Rect, context: BlockContext) {
    BlockEngine.prepare(self, context: context).draw(into: &list, in: rect)
  }
}
