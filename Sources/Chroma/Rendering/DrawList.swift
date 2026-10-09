import ChromaFont

public struct DrawList: Sendable, Codable {
  public private(set) var commands: [DrawEntry] = []

  public init() {}

  public init(commands: [DrawEntry]) {
    self.commands = commands
  }

  /// Reuse command storage when no previous frame still owns it. Array's value
  /// semantics keep previously returned frames unchanged when they are retained.
  public mutating func removeAll(keepingCapacity: Bool = true) {
    commands.removeAll(keepingCapacity: keepingCapacity)
  }

  public mutating func append(_ quad: DrawQuad) {
    commands.append(.quad(quad))
  }

  public mutating func fillRect(_ rect: Rect, color: Color) {
    append(DrawQuad(rect: rect, colors: CornerColors(color)))
  }

  public mutating func strokeRect(_ rect: Rect, width: Float, color: Color) {
    append(DrawQuad(rect: rect, colors: CornerColors(color), borderThickness: width))
  }

  public mutating func fillRoundedRect(_ rect: Rect, radius: Float, color: Color) {
    fillRoundedRect(rect, radii: CornerRadii(radius), color: color)
  }

  public mutating func fillRoundedRect(_ rect: Rect, radii: CornerRadii, color: Color) {
    append(DrawQuad(rect: rect, colors: CornerColors(color), radii: radii))
  }

  public mutating func strokeRoundedRect(_ rect: Rect, radius: Float, width: Float, color: Color) {
    strokeRoundedRect(rect, radii: CornerRadii(radius), width: width, color: color)
  }

  public mutating func strokeRoundedRect(
    _ rect: Rect, radii: CornerRadii, width: Float, color: Color
  ) {
    append(DrawQuad(rect: rect, colors: CornerColors(color), radii: radii, borderThickness: width))
  }

  public mutating func text(
    _ text: String, at position: Point, color: Color, scale: Float = 1
  ) {
    guard scale > 0, scale.isFinite else { return }
    let atlas = HighResolutionFontAtlas()
    let metrics = FontMetrics()
    var x = position.x
    for character in text {
      let (u0, v0, u1, v1) = atlas.glyphUV(character)
      append(
        DrawQuad(
          rect: Rect(
            x: x, y: position.y, width: metrics.glyphWidth * scale,
            height: metrics.glyphHeight * scale),
          sourceRect: Rect(x: u0, y: v0, width: u1 - u0, height: v1 - v0),
          texture: .fontAtlas, colors: CornerColors(color)))
      x += metrics.cellAdvance * scale
    }
  }

  public mutating func image(
    _ image: ImageResource, in destination: Rect,
    scaling: ImageScaling = .contain, alignment: ImageAlignment = .center
  ) {
    guard let rect = scaling.drawRect(sourceSize: image.size, in: destination, alignment: alignment),
      let visible = rect.intersection(destination)
    else { return }
    let source = Rect(
      x: (visible.minX - rect.minX) / rect.size.width,
      y: (visible.minY - rect.minY) / rect.size.height,
      width: visible.size.width / rect.size.width,
      height: visible.size.height / rect.size.height)
    append(DrawQuad(rect: visible, sourceRect: source, texture: .image(image)))
  }

  public mutating func pushClip(_ rect: Rect) { commands.append(.pushClip(rect)) }
  public mutating func popClip() { commands.append(.popClip) }
}
