public struct FontMetrics: Equatable, Sendable {
  public var glyphWidth: Float = 20
  public var glyphHeight: Float = 28
  // The readable system face occupies a narrower advance than the 20 px atlas
  // canvas. Drawing the full canvas on a 16 px advance removes the typewriter-
  // like tracking while retaining room for antialiased glyph edges.
  public var readableAdvance: Float = 16
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
