public struct Image {
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

  func sizeThatFits(_ proposal: Size, context: LayoutContext) -> Size {
    resource.size
  }

  func paint(into drawList: inout DrawList, in rect: Rect, context: LayoutContext) {
    drawList.image(resource, in: rect, scaling: scaling, alignment: alignment)
  }
}
