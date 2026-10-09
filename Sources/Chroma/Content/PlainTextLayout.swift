struct PlainTextLayout {
  let rect: Rect
  let cellWidth: Float
  let lineHeight: Float
  /// One immutable snapshot for hit testing, caret motion, and painting.
  let snapshot: TextLayoutSnapshot
  var layout: TextLayout { snapshot.layout }

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

  func selectionOffset(at point: Point) -> Int {
    if let offset = hitTest(point: point) { return offset }
    if point.y < rect.minY { return 0 }
    if point.y >= rect.maxY { return layout.characterCount }
    return point.x >= rect.maxX ? layout.characterCount : 0
  }
}
