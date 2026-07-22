/// Layout information for a plain `Text` block, stored in the registry each
/// frame so the selection manager can hit-test and extract text during drags.
struct PlainTextLayout: Equatable {
  var text: String
  var rect: Rect
  var cellWidth: Float
  var lineHeight: Float
  var scale: Float

  /// Returns the caret index nearest the given point, or nil if outside.
  ///
  /// The selection end is exclusive, so including the last character
  /// requires reaching `text.utf8.count`. Snapping to the nearest cell
  /// boundary makes that reachable: `Rect.contains` excludes the rect's
  /// `maxX` edge, so flooring could never produce the end index and the
  /// final character could never be selected.
  func hitTest(point: Point) -> Int? {
    guard rect.contains(point) else { return nil }
    let xOffset = point.x - rect.minX
    let col = Int((xOffset / cellWidth).rounded(.toNearestOrAwayFromZero))
    return max(0, min(col, text.utf8.count))
  }

  /// Returns the substring for a [from, to) column range.
  func textInRange(from: Int, to: Int) -> String {
    let utf8 = Array(text.utf8)
    let s = max(0, min(from, utf8.count))
    let e = max(s, min(to, utf8.count))
    guard s < e else { return "" }
    return String(decoding: utf8[s..<e], as: UTF8.self)
  }
}

/// Per-frame registry of `PlainTextLayout`s, populated during draw and
/// queried for hit-testing during drag selection.
@MainActor
enum PlainTextLayoutRegistry {
  private static var layouts: [WidgetID: PlainTextLayout] = [:]

  static func register(_ id: WidgetID, layout: PlainTextLayout) {
    layouts[id] = layout
  }

  static func layout(for id: WidgetID) -> PlainTextLayout? {
    layouts[id]
  }

  /// The (WidgetID, layout) pair whose rect contains the given point, or nil.
  static func entry(at point: Point) -> (WidgetID, PlainTextLayout)? {
    for (id, layout) in layouts where layout.rect.contains(point) {
      return (id, layout)
    }
    return nil
  }

  static func clear() {
    layouts.removeAll()
  }
}

/// Tracks drag-based text selection across frames, reading drag state from
/// `Interaction` and mapping it to character ranges in registered plain-text
/// layouts.
@MainActor
public final class TextSelectionManager {
  public static let shared = TextSelectionManager()

  /// The rect of the layout where this drag started.
  private var originLayoutRect: Rect? = nil
  private var originLayoutID: WidgetID? = nil
  private(set) var selectionStart: Int?
  private(set) var selectionEnd: Int?
  public var isSelecting: Bool = false

  private init() {}

  /// Call at the start of each frame to update selection from drag state.
  func updateFromDrag() {
    let interaction = Interaction.current
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
      if let (id, layout) = PlainTextLayoutRegistry.entry(at: origin) {
        originLayoutRect = layout.rect
        originLayoutID = id
        selectionStart = layout.hitTest(point: origin)
      }
    }
    guard originLayoutRect != nil,
      let layoutID = originLayoutID,
      let layout = PlainTextLayoutRegistry.layout(for: layoutID),
      selectionStart != nil
    else { return }

    if let endHit = layout.hitTest(point: current) {
      selectionEnd = endHit
    } else if current.y > layout.rect.maxY {
      selectionEnd = layout.text.utf8.count
    } else if current.y < layout.rect.minY {
      selectionEnd = 0
    } else if current.x >= layout.rect.maxX {
      // Dragging past the end of the text selects through the last cell.
      selectionEnd = layout.text.utf8.count
    } else if current.x < layout.rect.minX {
      selectionEnd = 0
    }
  }

  /// Returns the normalized [from, to) column range if one is active.
  func selection(for layout: PlainTextLayout) -> (from: Int, to: Int)? {
    guard let rect = originLayoutRect, rect == layout.rect else { return nil }
    guard let start = selectionStart, let end = selectionEnd else { return nil }
    if start <= end { return (start, end) }
    return (end, start)
  }

  /// Returns the currently selected text, or nil.
  public func selectedText() -> String? {
    guard originLayoutRect != nil,
      let layoutID = originLayoutID,
      let layout = PlainTextLayoutRegistry.layout(for: layoutID),
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
