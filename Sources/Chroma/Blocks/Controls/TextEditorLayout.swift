@MainActor
struct TextEditorLayout {
  let layout: TextLayout
  let rect: Rect
  let inner: Rect
  let scale: Float
  let cellWidth: Float
  let lineHeight: Float
  let visibleCount: Int
  let singleLine: Bool

  init(editor: TextEditor, layout: TextLayout, rect: Rect, context: BlockContext) {
    self.layout = layout
    self.rect = rect
    scale = editor.fontScale * context.textScale
    cellWidth = context.fontMetrics.cellAdvance * scale
    lineHeight = context.fontMetrics.lineAdvance * scale
    singleLine = editor.singleLine
    inner = Rect(
      x: rect.minX + editor.padding, y: rect.minY + editor.padding + (singleLine ? 1 : 0),
      width: max(0, rect.size.width - editor.padding * 2),
      height: singleLine ? context.fontMetrics.glyphHeight * scale : max(0, rect.size.height - editor.padding * 2))
    visibleCount =
      singleLine || !lineHeight.isFinite || lineHeight <= 0
      ? 1 : max(1, Int(min(Float(Int32.max), inner.size.height / lineHeight)))
  }

  var isValid: Bool { cellWidth.isFinite && cellWidth > 0 && lineHeight.isFinite && lineHeight > 0 }

  func horizontalOffset(_ caret: Int?) -> Float {
    guard singleLine, let caret else { return 0 }
    return min(0, inner.size.width - cellWidth - Float(caret) * cellWidth)
  }

  func firstRow(_ caret: Int?) -> Int {
    guard let caret else { return 0 }
    return max(0, min(layout.lines.count - visibleCount, layout.row(containing: caret) - visibleCount + 1))
  }

  func pointerOffset(_ point: Point, caret: Int?, interaction: Interaction) -> Int {
    if !singleLine, interaction.isProcessingDrag {
      var row = interaction.textDragViewportRow ?? firstRow(caret)
      if interaction.textDragAnchor != nil && point == interaction.dragCurrent {
        if point.y >= inner.maxY {
          row = min(max(0, layout.lines.count - visibleCount), row + 1)
        } else if point.y < inner.minY {
          row = max(0, row - 1)
        }
      }
      interaction.textDragViewportRow = row
    }
    return layout.offset(
      row: singleLine
        ? 0
        : (interaction.textDragViewportRow ?? firstRow(caret))
          + Int(((point.y - inner.minY) / lineHeight).rounded(.down)),
      column: Int(((point.x - inner.minX - horizontalOffset(caret)) / cellWidth).rounded(.toNearestOrAwayFromZero)))
  }

  func prepare(editor: TextEditor, context: BlockContext, text: @escaping @MainActor () -> String) {
    guard isValid else { return }
    _ = context.textInputState(
      in: rect, text: text, onChange: editor.onChange, onSubmit: editor.onSubmit,
      onEndEditing: editor.onEndEditing, onTextEvent: editor.onTextEvent,
      pointerOffset: { point, caret in pointerOffset(point, caret: caret, interaction: context.interaction) },
      verticalOffset: { layout.verticalOffset($0, direction: $1) },
      submitInsertsNewline: !singleLine && editor.onSubmit == nil)
  }

  func paint(editor: TextEditor, context: BlockContext, into list: inout DrawList) {
    guard isValid else { return }
    let interaction = context.interaction
    let editing = interaction.editingLeaf == context.widgetID
    let caret = editing ? interaction.caretOffset : nil
    let selection = editing ? interaction.textSelectionRange : nil
    let style = editor.style ?? context.theme.textEditor
    list.textInputBackground(in: rect, style: style, editing: editing && interaction.isTextEditing)
    if interaction.selectedLeafID == context.widgetID {
      list.strokeRoundedRect(rect, radius: style.cornerRadius, width: 2, color: context.theme.focus.ring)
    }
    list.pushClip(inner)
    defer { list.popClip() }
    if layout.text.isEmpty && !(editing && interaction.isTextEditing) {
      list.text(editor.placeholder, at: inner.origin, color: style.placeholder, scale: scale)
      return
    }
    let first =
      interaction.isProcessingDrag && editing
      ? interaction.textDragViewportRow ?? firstRow(caret) : firstRow(caret)
    for index in first..<min(layout.lines.count, first + visibleCount) {
      let line = layout.lines[index]
      let origin = Point(x: inner.minX + horizontalOffset(caret), y: inner.minY + Float(index - first) * lineHeight)
      let highlight = selection.flatMap { range -> Rect? in
        let lower = max(line.range.lowerBound, range.lowerBound)
        let upper = min(line.range.upperBound, range.upperBound)
        guard lower < upper else { return nil }
        return Rect(
          x: origin.x + Float(lower - line.range.lowerBound) * cellWidth, y: origin.y,
          width: Float(upper - lower) * cellWidth, height: lineHeight)
      }
      list.textInputLine(
        line.text, at: origin, scale: scale, foreground: style.foreground,
        selection: highlight, theme: context.theme.focus)
    }
    if let caret, selection == nil {
      let row = layout.row(containing: caret)
      let caretRect = Rect(
        x: inner.minX + horizontalOffset(caret) + Float(caret - layout.lines[row].range.lowerBound) * cellWidth,
        y: inner.minY + Float(row - first) * lineHeight, width: max(1, scale), height: lineHeight)
      context.animate(into: &list, isActive: interaction.isTextEditing) { list, _ in
        if !interaction.isTextEditing || context.caretVisible { list.fillRect(caretRect, color: style.caret) }
      }
    }
  }
}

extension TextEditor {
  @MainActor func columns(width: Float, context: BlockContext) -> Int? {
    let cell = context.fontMetrics.cellAdvance * fontScale * context.textScale
    guard !singleLine, cell.isFinite, cell > 0, width.isFinite else { return nil }
    return Int(min(Float(Int32.max), max(1, (width - 2 * padding) / cell)))
  }

  @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext, layout: TextLayout) -> Size {
    let scale = fontScale * context.textScale
    if singleLine {
      return Size(width: proposal.width, height: context.fontMetrics.glyphHeight * scale + 2 * padding + 2)
    }
    let count = min(lineLimits.upperBound, max(lineLimits.lowerBound, layout.lines.count))
    return Size(width: proposal.width, height: Float(count) * context.fontMetrics.lineAdvance * scale + 2 * padding)
  }
}
