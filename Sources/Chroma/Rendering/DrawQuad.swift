public struct DrawQuad: Equatable, Sendable, Codable {
  public var rect: Rect
  /// Normalized texture coordinates.
  public var sourceRect: Rect
  public var texture: TextureResource
  public var colors: CornerColors
  public var radii: CornerRadii
  /// Zero fills the quad; positive values hollow out its interior.
  public var borderThickness: Float
  public var edgeSoftness: Float

  public init(
    rect: Rect,
    sourceRect: Rect = Rect(x: 0, y: 0, width: 1, height: 1),
    texture: TextureResource = .white,
    colors: CornerColors = CornerColors(.white),
    radii: CornerRadii = .zero,
    borderThickness: Float = 0,
    edgeSoftness: Float = 0
  ) {
    self.rect = rect
    self.sourceRect = sourceRect
    self.texture = texture
    self.colors = colors
    self.radii = radii
    self.borderThickness = borderThickness
    self.edgeSoftness = edgeSoftness
  }
}

public enum TextureResource: Equatable, Sendable, Codable {
  case white
  case fontAtlas
  case image(ImageResource)
}

public struct CornerColors: Equatable, Sendable, Codable {
  public var topLeft: Color
  public var topRight: Color
  public var bottomRight: Color
  public var bottomLeft: Color

  public init(topLeft: Color, topRight: Color, bottomRight: Color, bottomLeft: Color) {
    self.topLeft = topLeft
    self.topRight = topRight
    self.bottomRight = bottomRight
    self.bottomLeft = bottomLeft
  }

  public init(_ color: Color) {
    self.init(topLeft: color, topRight: color, bottomRight: color, bottomLeft: color)
  }
}

public enum DrawEntry: Equatable, Sendable, Codable {
  case quad(DrawQuad)
  case pushClip(Rect)
  case popClip
}
