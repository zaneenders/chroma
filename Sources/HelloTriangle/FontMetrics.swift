/// Metrics of the 5x7 bitmap font used for bootstrapping.
///
/// Shared between UI-facing code (layout and measurement) and backends
/// (glyph expansion), so both agree on text geometry without the UI layer
/// touching the font atlas.
struct FontMetrics: Equatable {
  var glyphWidth: Float = 5
  var glyphHeight: Float = 7
  var glyphSpacing: Float = 1
  /// Vertical distance between the tops of consecutive lines.
  var lineAdvance: Float = 9

  /// Horizontal advance per character cell.
  var cellAdvance: Float { glyphWidth + glyphSpacing }

  /// Pixel size of a single line of ASCII text at the given scale.
  func measure(_ text: String, scale: Float = 1) -> Size {
    Size(width: Float(text.utf8.count) * cellAdvance * scale, height: glyphHeight * scale)
  }
}
