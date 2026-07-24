/// Metrics of Chroma's hand-authored 20×28 bitmap font.
///
/// Shared between UI-facing code (layout and measurement) and backends
/// (glyph expansion), so both agree on text geometry without the UI layer
/// touching the font atlas.
public struct FontMetrics: Equatable, Sendable {
  public var glyphWidth: Float = 20
  public var glyphHeight: Float = 28
  public var glyphSpacing: Float = 2
  /// Vertical distance between the tops of consecutive lines.
  public var lineAdvance: Float = 32

  public init() {}

  /// Horizontal advance per character cell.
  public var cellAdvance: Float { glyphWidth + glyphSpacing }

  /// Pixel size of a single line of ASCII text at the given scale.
  public func measure(_ text: String, scale: Float = 1) -> Size {
    Size(width: Float(text.utf8.count) * cellAdvance * scale, height: glyphHeight * scale)
  }
}
