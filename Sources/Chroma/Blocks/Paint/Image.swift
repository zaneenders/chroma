public struct Image: PaintableBlock {
  public var resource: ImageResource
  public var scaling: ImageScaling
  public var alignment: ImageAlignment

  public init(
    _ resource: ImageResource,
    scaling: ImageScaling = .contain,
    alignment: ImageAlignment = .center
  ) {
    self.resource = resource
    self.scaling = scaling
    self.alignment = alignment
  }

  public var focusRule: FocusRule { .standard }

  public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    resource.size
  }

  public var expandsHorizontally: Bool { false }
  public var expandsVertically: Bool { false }

  public func register(in rect: Rect, context: BlockContext) {}

  public func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    draw(into: &drawList, in: rect, context: context)
  }

  public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    drawList.image(resource, in: rect, scaling: scaling, alignment: alignment)
  }
}
