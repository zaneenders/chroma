/// Immutable shaping shared by measurement, interaction registration and painting.
/// Monospaced line breaking depends on text and column count; font metrics and scale
/// determine those columns and the geometry surrounding this snapshot.
final class TextLayoutSnapshot: Equatable, Sendable {
  let text: String
  let columns: Int?
  let layout: TextLayout

  init(_ text: String, columns: Int?) {
    self.text = text
    self.columns = columns
    layout = TextLayout(text, columns: columns)
  }

  static func == (lhs: TextLayoutSnapshot, rhs: TextLayoutSnapshot) -> Bool {
    lhs === rhs || (lhs.text == rhs.text && lhs.columns == rhs.columns)
  }
}

/// One resolved operation owns one preparation. The single-entry cache is bounded,
/// checks all shaping inputs on every read, and expires with the resolved tree.
/// Registered pointer handlers retain only their immutable snapshot, not this cache.
@MainActor
final class TextLayoutPreparation {
  private(set) var snapshot: TextLayoutSnapshot?

  func resolve(_ text: String, columns: Int?) -> TextLayoutSnapshot {
    if let snapshot, snapshot.text == text, snapshot.columns == columns { return snapshot }
    PipelineMetrics.record(.textLayout)
    let snapshot = TextLayoutSnapshot(text, columns: columns)
    self.snapshot = snapshot
    return snapshot
  }
}
