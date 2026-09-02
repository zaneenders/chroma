public struct Image: PrimitiveBlock {
  public var resource: ImageResource
  public var contentMode: ImageContentMode

  public init(_ resource: ImageResource, contentMode: ImageContentMode = .stretch) {
    self.resource = resource
    self.contentMode = contentMode
  }

  public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    proposal
  }

  public var expandsHorizontally: Bool { true }
  public var expandsVertically: Bool { true }

  public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    drawList.image(resource, in: rect, contentMode: contentMode)
  }
}
