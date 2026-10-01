struct VariableHeightIndex {
  let count: Int
  let estimatedHeight: Double
  private var measuredHeights: [Int: Double] = [:]
  private var deltas: [Int: Double] = [:]

  init(count: Int, estimatedHeight: Double) {
    precondition(count >= 0 && count < Int.max)
    precondition(estimatedHeight.isFinite && estimatedHeight > 0)
    precondition((Double(count) * estimatedHeight).isFinite)
    self.count = count
    self.estimatedHeight = estimatedHeight
  }

  var measuredCount: Int { measuredHeights.count }
  var totalHeight: Double { position(of: count) }

  func height(at index: Int) -> Double {
    precondition((0..<count).contains(index))
    return measuredHeights[index] ?? estimatedHeight
  }

  func position(of index: Int) -> Double {
    precondition((0...count).contains(index))
    var position = Double(index) * estimatedHeight
    var cursor = index
    while cursor > 0 {
      position += deltas[cursor, default: 0]
      cursor -= cursor & -cursor
    }
    return position
  }

  mutating func measure(_ index: Int, height: Double) {
    precondition((0..<count).contains(index))
    precondition(height.isFinite && height > 0)
    let delta = height - self.height(at: index)
    measuredHeights[index] = height
    var cursor = index + 1
    while cursor <= count {
      deltas[cursor, default: 0] += delta
      let step = cursor & -cursor
      if step > count - cursor { break }
      cursor += step
    }
  }

  // Fenwick binary lifting includes the implicit estimate at each tree node.
  func row(at offset: Double) -> Int {
    precondition(offset.isFinite)
    guard count > 0 else { return 0 }
    let offset = max(0, offset)
    var index = 0
    var position: Double = 0
    var step = 1
    while step <= count / 2 { step *= 2 }
    while step > 0 {
      if step <= count - index {
        let next = index + step
        let extent = Double(next & -next) * estimatedHeight + deltas[next, default: 0]
        if position + extent <= offset {
          index = next
          position += extent
        }
      }
      step /= 2
    }
    return min(index, count - 1)
  }

  func visibleRange(offset: Double, height: Double, overscan: Int = 1) -> Range<Int> {
    precondition(offset.isFinite && height.isFinite && overscan >= 0)
    guard count > 0, height > 0 else { return 0..<0 }
    let first = row(at: offset)
    let bottom = offset + height
    precondition(bottom.isFinite)
    let last = row(at: bottom)
    let end = position(of: last) >= bottom ? last : last + 1
    return max(0, first - min(first, overscan))..<min(count, end + min(count - end, overscan))
  }
}
