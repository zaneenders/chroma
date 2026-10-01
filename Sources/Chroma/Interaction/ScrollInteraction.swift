@MainActor
extension Interaction {
  func scrollDelta(in rect: Rect, horizontal: Bool = false) -> Point {
    guard clippedRect(rect).contains(input.pointerPosition) else { return .zero }
    return Point(x: horizontal ? input.scrollDelta.x : 0, y: input.scrollDelta.y)
  }

  func registerScrollInput(id: WidgetID, rect: Rect, horizontal: Bool = false) {
    let rect = clippedRect(rect)
    building.inputHandlers[id] = { [weak self] in
      guard let self else { return }
      let delta = self.scrollDelta(in: rect, horizontal: horizontal)
      var state = self.scrollStates[id, default: ScrollState()]
      state.offset.x -= delta.x
      state.offset.y -= delta.y
      state.clampOffset()
      self.scrollStates[id] = state
    }
  }

  func recordScrollRow(id: WidgetID, leafID: WidgetID, rowKey: StructuralKey, rect: Rect) {
    scrollStates[id, default: ScrollState()].rows[leafID] = rect
    scrollStates[id, default: ScrollState()].rowKeys[leafID] = rowKey
  }
  struct ScrollState {
    var offset = Point.zero
    var limit = Point.zero
    var pendingReveal: Rect?
    var rows: [WidgetID: Rect] = [:]
    var rowKeys: [WidgetID: StructuralKey] = [:]
    var layout: ScrollLayout?

    mutating func clampOffset() {
      offset.x = min(max(0, offset.x), limit.x)
      offset.y = min(max(0, offset.y), limit.y)
    }
  }

  struct ScrollLayout: Equatable {
    enum Rows: Equatable {
      case uniform(count: Int, height: Float, keys: [StructuralKey]?)
      case variable(VariableScrollRows)

      static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.uniform(let a, let h, let k), .uniform(let b, let j, let l)): a == b && h == j && k == l
        case (.variable(let a), .variable(let b)): a === b
        default: false
        }
      }
    }

    var width: Float
    var spacing: Float
    var rows: Rows

    func index(of key: StructuralKey) -> Int? {
      switch rows {
      case .uniform(let count, _, let keys):
        if let keys { return keys.firstIndex(of: key) }
        guard let index = key.value as? Int, index >= 0, index < count else { return nil }
        return index
      case .variable(let rows): return rows.keys.firstIndex(of: key)
      }
    }

    func position(of index: Int) -> Float {
      switch rows {
      case .uniform(_, let height, _): Float(index) * (height + spacing)
      case .variable(let rows): rows.starts[index]
      }
    }
  }

  final class VariableScrollRows {
    let keys: [StructuralKey]
    let starts: [Float]
    let heights: [Float]
    let height: Float

    init(keys: [StructuralKey], heights: [Float], spacing: Float) {
      self.keys = keys
      self.heights = heights
      var starts: [Float] = []
      starts.reserveCapacity(heights.count)
      var y: Float = 0
      for height in heights {
        starts.append(y)
        y += height + spacing
      }
      self.starts = starts
      self.height = heights.isEmpty ? 0 : y - spacing
    }

    func firstRow(endingAtOrAfter top: Float) -> Int {
      var low = 0
      var high = starts.count
      while low < high {
        let mid = low + (high - low) / 2
        if starts[mid] + heights[mid] < top { low = mid + 1 } else { high = mid }
      }
      return low
    }

    func firstRow(startingAfter bottom: Float) -> Int {
      var low = 0
      var high = starts.count
      while low < high {
        let mid = low + (high - low) / 2
        if starts[mid] <= bottom { low = mid + 1 } else { high = mid }
      }
      return low
    }
  }

  func updateScrollLayout(id: WidgetID, layout: ScrollLayout) {
    if let previous = scrollStates[id]?.layout, previous != layout {
      scrollStates[id, default: ScrollState()].rows = [:]
      scrollStates[id, default: ScrollState()].rowKeys = [:]
    }
    scrollStates[id, default: ScrollState()].layout = layout
  }
}
