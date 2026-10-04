import Chroma

struct MarkdownLayout {
  var lines: [VisualLine]
  var lineHeight: Float
  var cellWidth: Float
  var scale: Float
  var hasLeadingGap = false
  var rect: Rect

  // Soft wraps consume no characters; explicit separators do. The leading
  // inter-block spacer is visual only and never enters the copied text.
  var text: String {
    lines.enumerated().map { index, line in
      line.runs.map(\.text).joined() + separator(after: index)
    }.joined()
  }

  private func separator(after row: Int) -> String {
    guard row < lines.count - 1 else { return "" }
    if row == 0, hasLeadingGap { return "" }
    return lines[row].trailingText
  }

  private var starts: [Int] {
    var offset = 0
    return lines.indices.map { row in
      defer { offset += lines[row].columnCount + separator(after: row).count }
      return offset
    }
  }

  func position(at offset: Int) -> (row: Int, column: Int) {
    guard !lines.isEmpty else { return (0, 0) }
    let offset = max(0, min(offset, text.count))
    let starts = starts
    let row = starts.lastIndex(where: { $0 <= offset }) ?? 0
    return (row, min(lines[row].columnCount, offset - starts[row]))
  }

  func hitTest(_ point: Point) -> Int {
    guard !lines.isEmpty, lineHeight > 0, cellWidth > 0 else { return 0 }
    let row = max(0, min(lines.count - 1, Int((point.y - rect.minY) / lineHeight)))
    let column = max(
      0,
      min(
        lines[row].columnCount,
        Int(((point.x - rect.minX) / cellWidth).rounded(.toNearestOrAwayFromZero))))
    return starts[row] + column
  }

  func verticalOffset(_ offset: Int, direction: Int) -> Int {
    guard !lines.isEmpty else { return 0 }
    let current = position(at: offset)
    let row = current.row + direction
    if row < 0 { return 0 }
    if row >= lines.count { return text.count }
    return starts[row] + min(current.column, lines[row].columnCount)
  }

  func draw(into drawList: inout DrawList, theme: ChromaTheme, selection: TextInputState) {
    let starts = starts
    for (index, line) in lines.enumerated() {
      let y = rect.minY + Float(index) * lineHeight
      if line.kind == .code {
        drawList.fillRect(
          Rect(x: rect.minX, y: y, width: rect.size.width, height: lineHeight),
          color: theme.surface)
      }
      let lower = max(starts[index], selection.selectionRange?.lowerBound ?? 0)
      let upper = min(starts[index] + line.columnCount, selection.selectionRange?.upperBound ?? 0)
      var highlight: Rect?
      if lower < upper {
        let selected = Rect(
          x: rect.minX + Float(lower - starts[index]) * cellWidth, y: y,
          width: Float(upper - lower) * cellWidth, height: lineHeight)
        drawList.fillRect(selected, color: theme.focus.selectionBackground)
        highlight = selected
      }
      var x = rect.minX
      for run in line.runs {
        drawList.text(run.text, at: Point(x: x, y: y), color: run.color, scale: scale)
        if let highlight {
          drawList.pushClip(highlight)
          drawList.text(
            run.text, at: Point(x: x, y: y),
            color: theme.focus.selectionForeground, scale: scale)
          drawList.popClip()
        }
        x += Float(run.text.count) * cellWidth
      }
    }
    if selection.selectionRange?.isEmpty != false, let caret = selection.caretOffset, !lines.isEmpty {
      let position = position(at: caret)
      drawList.fillRect(
        Rect(
          x: rect.minX + Float(position.column) * cellWidth,
          y: rect.minY + Float(position.row) * lineHeight, width: 1, height: lineHeight),
        color: theme.focus.ring)
    }
  }
}
