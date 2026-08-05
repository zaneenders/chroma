public struct Spacer: PrimitiveBlock {
  public init() {}

  public var expandsHorizontally: Bool { true }
  public var expandsVertically: Bool { true }

  public func sizeThatFits(_ proposal: Size) -> Size { proposal }
  public func draw(into drawList: inout DrawList, in rect: Rect) {}
}
