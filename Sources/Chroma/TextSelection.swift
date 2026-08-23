struct PlainTextLayout: Equatable {
  var text: String
  var rect: Rect
  var cellWidth: Float
  var lineHeight: Float
  var scale: Float

  func hitTest(point: Point) -> Int? {
    guard rect.contains(point), cellWidth > 0, cellWidth.isFinite else { return nil }
    let xOffset = point.x - rect.minX
    let col = Int((xOffset / cellWidth).rounded(.toNearestOrAwayFromZero))
    return max(0, min(col, text.count))
  }

  func textInRange(from: Int, to: Int) -> String {
    let characters = Array(text)
    let s = max(0, min(from, characters.count))
    let e = max(s, min(to, characters.count))
    guard s < e else { return "" }
    return String(characters[s..<e])
  }
}

@MainActor
struct PlainTextLayoutRegistry {
  private var layouts: [WidgetID: PlainTextLayout] = [:]

  mutating func register(_ id: WidgetID, layout: PlainTextLayout) {
    layouts[id] = layout
  }

  func layout(for id: WidgetID) -> PlainTextLayout? {
    layouts[id]
  }

  func entry(at point: Point) -> (WidgetID, PlainTextLayout)? {
    for (id, layout) in layouts where layout.rect.contains(point) {
      return (id, layout)
    }
    return nil
  }

  mutating func clear() {
    layouts.removeAll()
  }
}

@MainActor
public final class TextSelectionManager {
  private var originLayoutRect: Rect? = nil
  private var originLayoutID: WidgetID? = nil
  private(set) var selectionStart: Int?
  private(set) var selectionEnd: Int?
  public private(set) var isSelecting: Bool = false

  var layoutRegistry = PlainTextLayoutRegistry()

  public init() {}

  func updateFromDrag(interaction: Interaction) {
    guard interaction.isDragging else {
      if isSelecting { isSelecting = false }
      return
    }
    if !isSelecting {
      isSelecting = true
      originLayoutRect = nil
      originLayoutID = nil
      selectionStart = nil
      selectionEnd = nil
    }
    guard let origin = interaction.dragOrigin else { return }
    let current = interaction.dragCurrent

    if originLayoutRect == nil {
      if let (id, layout) = layoutRegistry.entry(at: origin) {
        originLayoutRect = layout.rect
        originLayoutID = id
        selectionStart = layout.hitTest(point: origin)
      }
    }
    guard originLayoutRect != nil,
      let layoutID = originLayoutID,
      let layout = layoutRegistry.layout(for: layoutID),
      selectionStart != nil
    else { return }

    if let endHit = layout.hitTest(point: current) {
      selectionEnd = endHit
    } else if current.y > layout.rect.maxY {
      selectionEnd = layout.text.count
    } else if current.y < layout.rect.minY {
      selectionEnd = 0
    } else if current.x >= layout.rect.maxX {
      selectionEnd = layout.text.count
    } else if current.x < layout.rect.minX {
      selectionEnd = 0
    }
  }

  func selection(for layout: PlainTextLayout) -> (from: Int, to: Int)? {
    guard let rect = originLayoutRect, rect == layout.rect else { return nil }
    guard let start = selectionStart, let end = selectionEnd else { return nil }
    if start <= end { return (start, end) }
    return (end, start)
  }

  public func selectAll() {
    guard let layoutID = originLayoutID,
      let layout = layoutRegistry.layout(for: layoutID)
    else { return }
    originLayoutRect = layout.rect
    selectionStart = 0
    selectionEnd = layout.text.count
    isSelecting = false
  }

  package func selectAll(at point: Point) {
    if originLayoutID == nil, let (id, layout) = layoutRegistry.entry(at: point) {
      originLayoutID = id
      originLayoutRect = layout.rect
    }
    selectAll()
  }

  public func selectedText() -> String? {
    guard originLayoutRect != nil,
      let layoutID = originLayoutID,
      let layout = layoutRegistry.layout(for: layoutID),
      let start = selectionStart,
      let end = selectionEnd
    else { return nil }
    let s = min(start, end)
    let e = max(start, end)
    return layout.textInRange(from: s, to: e)
  }

  func clear() {
    originLayoutRect = nil
    originLayoutID = nil
    selectionStart = nil
    selectionEnd = nil
    isSelecting = false
  }
}
