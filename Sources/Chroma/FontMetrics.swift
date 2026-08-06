public struct FontMetrics: Equatable, Sendable {
  public var glyphWidth: Float = 20
  public var glyphHeight: Float = 28
  public var glyphSpacing: Float = 2
  public var lineAdvance: Float = 32

  public init() {}

  public var cellAdvance: Float { glyphWidth + glyphSpacing }

  public func measure(_ text: String, scale: Float = 1) -> Size {
    Size(width: Float(text.count) * cellAdvance * scale, height: glyphHeight * scale)
  }
}
