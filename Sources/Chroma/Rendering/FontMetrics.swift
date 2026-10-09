public struct FontMetrics: Equatable, Sendable {
  public var glyphWidth: Float = 20
  public var glyphHeight: Float = 28
  public var cellAdvance: Float = 12
  public var lineAdvance: Float = 32

  public init() {}

  public func measure(_ text: String, scale: Float = 1) -> Size {
    var longestLine = 0
    var columns = 0
    var lineBreaks = 0
    for character in text {
      // Match TextLayout's grapheme-level newline handling, including CRLF.
      if character.isNewline {
        longestLine = max(longestLine, columns)
        columns = 0
        lineBreaks += 1
      } else {
        columns += 1
      }
    }
    return Size(
      width: Float(max(longestLine, columns)) * cellAdvance * scale,
      height: (glyphHeight + Float(lineBreaks) * lineAdvance) * scale)
  }
}
