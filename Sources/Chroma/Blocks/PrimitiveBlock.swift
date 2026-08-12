public protocol PrimitiveBlock: Block where Body == Never {
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
