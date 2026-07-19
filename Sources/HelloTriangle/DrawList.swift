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

/// The ordered drawing commands for one frame.
///
/// Application code appends commands; backends consume them without knowing
/// what produced them.
struct DrawList {
  private(set) var commands: [DrawCommand] = []

  mutating func text(_ text: String, at position: Point, color: Color, scale: Float = 1) {
    commands.append(.text(position: position, text: text, color: color, scale: scale))
  }
}
