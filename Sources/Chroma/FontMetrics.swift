public struct FontMetrics: Equatable, Sendable {
  public var glyphWidth: Float = 20
  public var glyphHeight: Float = 28
  // Bedstead's native monospace advance is 36 px in the 60 px rasterized face,
  // which maps to 12 logical points in Chroma's 20-point glyph canvas.
  public var readableAdvance: Float = 12
  public var glyphSpacing: Float = 0
  public var lineAdvance: Float = 32

  public init() {}

  public var cellAdvance: Float { readableAdvance }
  public var displayCellAdvance: Float { glyphWidth + glyphSpacing }

  public func advance(for face: FontFace) -> Float {
    face == .readable ? cellAdvance : displayCellAdvance
  }

  public func measure(_ text: String, scale: Float = 1, face: FontFace = .readable) -> Size {
    Size(width: Float(text.count) * advance(for: face) * scale, height: glyphHeight * scale)
  }
}
