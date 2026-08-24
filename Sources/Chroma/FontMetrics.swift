public struct FontMetrics: Equatable, Sendable {
  public var glyphWidth: Float = 20
  public var glyphHeight: Float = 28
  // The antialiased readable face includes generous side bearings, so a
  // slightly tighter cell gives body text normal letter spacing.
  public var readableAdvance: Float = 18
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
