/// Immutable shaping shared by measurement, interaction registration and painting.
/// Monospaced line breaking depends on text and column count; font metrics and scale
/// determine those columns and the geometry surrounding this snapshot.
final class TextLayoutSnapshot: Equatable, Sendable {
  let text: String
  let columns: Int?
  let layout: TextLayout
  let estimatedBytes: Int

  init(_ text: String, columns: Int?) {
    self.text = text
    self.columns = columns
    layout = TextLayout(text, columns: columns)
    // Budget original/copied UTF-8, spare line-array capacity and entry overhead.
    // This is a conservative storage estimate, not a measurement of heap usage.
    estimatedBytes = 256 + 2 * text.utf8.count + 2 * layout.lines.count * MemoryLayout<TextLayout.Line>.stride
  }

  static func == (lhs: TextLayoutSnapshot, rhs: TextLayoutSnapshot) -> Bool {
    lhs === rhs || (lhs.columns == rhs.columns && lhs.text.utf8.elementsEqual(rhs.text.utf8))
  }
}

/// A window-owned FIFO cache of immutable shaping, never callbacks or geometry.
/// Both limits bound retention; oversized layouts are usable but are not retained.
@MainActor
final class TextLayoutPreparation {
  private struct Key: Hashable {
    let text: String
    let columns: Int?

    // String's canonical equivalence must not replace the source's actual bytes.
    // Its synthesized hash remains valid: unequal keys may share a hash bucket.
    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.columns == rhs.columns && lhs.text.utf8.elementsEqual(rhs.text.utf8)
    }
  }

  private let entryLimit: Int
  private let byteLimit: Int
  private var snapshots: [Key: TextLayoutSnapshot] = [:]
  private var order: [Key] = []
  private(set) var estimatedBytes = 0
  var count: Int { snapshots.count }

  init(entryLimit: Int = 512, byteLimit: Int = 4 * 1024 * 1024) {
    precondition(entryLimit >= 0 && byteLimit >= 0)
    self.entryLimit = entryLimit
    self.byteLimit = byteLimit
  }

  func resolve(_ text: String, columns: Int?) -> TextLayoutSnapshot {
    let key = Key(text: text, columns: columns)
    if let snapshot = snapshots[key] { return snapshot }
    PipelineMetrics.record(.textLayout)
    let snapshot = TextLayoutSnapshot(text, columns: columns)
    guard entryLimit > 0, snapshot.estimatedBytes <= byteLimit else { return snapshot }
    while snapshots.count >= entryLimit || estimatedBytes > byteLimit - snapshot.estimatedBytes {
      if let removed = snapshots.removeValue(forKey: order.removeFirst()) {
        estimatedBytes -= removed.estimatedBytes
      }
    }
    snapshots[key] = snapshot
    order.append(key)
    estimatedBytes += snapshot.estimatedBytes
    return snapshot
  }

  func clear() {
    snapshots.removeAll()
    order.removeAll()
    estimatedBytes = 0
  }
}
