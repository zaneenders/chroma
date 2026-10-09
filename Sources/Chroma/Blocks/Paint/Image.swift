public struct Image: Block {
  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    buffer.image(self, context: context)
  }

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

  var focusRule: FocusRule { .standard }

  func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    resource.size
  }

  var expandsHorizontally: Bool { false }
  var expandsVertically: Bool { false }

  func register(in rect: Rect, context: BlockContext) {}

  func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    drawList.image(resource, in: rect, scaling: scaling, alignment: alignment)
  }
}
