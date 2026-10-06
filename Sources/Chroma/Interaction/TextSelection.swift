import Observation

struct PlainTextLayout: Equatable {
  let text: String
  let rect: Rect
  let cellWidth: Float
  let lineHeight: Float
  let scale: Float
  let columns: Int?
  /// Immutable snapshot shared by hit testing, caret motion, selection painting, and text painting.
  /// The registry replaces it during every update; it is never keyed by identity alone.
  let snapshot: TextLayoutSnapshot
  var layout: TextLayout { snapshot.layout }

  init(
    text: String, rect: Rect, cellWidth: Float, lineHeight: Float, scale: Float,
    columns: Int? = nil, snapshot: TextLayoutSnapshot? = nil
  ) {
    self.text = text
    self.rect = rect
    self.cellWidth = cellWidth
    self.lineHeight = lineHeight
    self.scale = scale
    self.columns = columns
    if let snapshot {
      precondition(snapshot.text == text && snapshot.columns == columns)
      self.snapshot = snapshot
    } else {
      self.snapshot = TextLayoutSnapshot(text, columns: columns)
    }
  }

  func hitTest(point: Point) -> Int? {
    guard rect.contains(point), cellWidth > 0, cellWidth.isFinite else { return nil }
    return layout.offset(
      row: Int((point.y - rect.minY) / max(1, lineHeight)),
      column: Int(((point.x - rect.minX) / cellWidth).rounded(.toNearestOrAwayFromZero)))
  }

  func position(at offset: Int) -> Point {
    let layout = layout
    let offset = max(0, min(offset, layout.characterCount))
    let row = layout.row(containing: offset)
    return Point(
      x: rect.minX + Float(offset - layout.lines[row].range.lowerBound) * cellWidth,
      y: rect.minY + Float(row) * lineHeight)
  }

  func verticalOffset(_ offset: Int, direction: Int) -> Int {
    layout.verticalOffset(offset, direction: direction)
  }

  func textInRange(from: Int, to: Int) -> String {
    let characters = Array(text)
    let s = max(0, min(from, characters.count))
    let e = max(s, min(to, characters.count))
    guard s < e else { return "" }
    return String(characters[s..<e])
  }
}

@Observable
@MainActor
public final class TextSelectionManager {
  public private(set) var selection: TextDocument.Selection?
  public private(set) var isSelecting = false
  @ObservationIgnored var documents: [TextID: TextDocument] = [:]

  public init() {}

  public func select(_ selection: TextDocument.Selection) {
    guard documents[selection.document]?.bounds(of: selection) != nil else { return }
    self.selection = selection
  }

  public func selectedText() -> String? {
    guard let selection else { return nil }
    let text = documents[selection.document]?.text(in: selection)
    return text?.isEmpty == false ? text : nil
  }

  public func selectAll() {
    guard let selection, let document = documents[selection.document],
      let first = document.runs.first, let last = document.runs.last
    else { return }
    self.selection = TextDocument.Selection(
      document: document.id, anchor: .init(run: first.id, offset: 0),
      active: .init(run: last.id, offset: last.text.count))
    isSelecting = false
  }

  func install(_ documents: [TextID: TextDocument]) {
    if let selection {
      let old = self.documents[selection.document]
      let new = documents[selection.document]
      // Without an edit mapping, even an equal-length replacement can invalidate offsets.
      if old != new || new?.bounds(of: selection) == nil { clear() }
    }
    self.documents = documents
  }

  func setSelecting(_ value: Bool) { isSelecting = value }

  public func clear() {
    selection = nil
    isSelecting = false
  }
}
