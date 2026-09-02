public struct DrawList: Sendable {
  public private(set) var commands: [DrawCommand] = []

  public init() {}

  public mutating func fillRect(_ rect: Rect, color: Color) {
    commands.append(.fillRect(rect: rect, color: color))
  }

  public mutating func strokeRect(_ rect: Rect, width: Float, color: Color) {
    commands.append(.strokeRect(rect: rect, width: width, color: color))
  }

  public mutating func fillRoundedRect(_ rect: Rect, radius: Float, color: Color) {
    fillRoundedRect(rect, radii: CornerRadii(radius), color: color)
  }

  public mutating func fillRoundedRect(_ rect: Rect, radii: CornerRadii, color: Color) {
    commands.append(.fillRoundedRect(rect: rect, radii: radii, color: color))
  }

  public mutating func strokeRoundedRect(_ rect: Rect, radius: Float, width: Float, color: Color) {
    strokeRoundedRect(rect, radii: CornerRadii(radius), width: width, color: color)
  }

  public mutating func strokeRoundedRect(
    _ rect: Rect, radii: CornerRadii, width: Float, color: Color
  ) {
    commands.append(.strokeRoundedRect(rect: rect, radii: radii, width: width, color: color))
  }

  public mutating func text(
    _ text: String,
    at position: Point,
    color: Color,
    scale: Float = 1,
    face: FontFace = .readable
  ) {
    commands.append(
      .text(position: position, text: text, color: color, scale: scale, face: face))
  }

  public mutating func image(
    _ image: ImageResource,
    in rect: Rect,
    contentMode: ImageContentMode = .stretch
  ) {
    commands.append(.image(rect: rect, image: image, contentMode: contentMode))
  }

  public mutating func pushClip(_ rect: Rect) {
    commands.append(.pushClip(rect))
  }

  public mutating func popClip() {
    commands.append(.popClip)
  }
}
