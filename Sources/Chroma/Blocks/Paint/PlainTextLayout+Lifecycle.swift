extension PlainTextLayout {
  @MainActor func prepare(text: Text, context: BlockContext) {
    let id = text.selectionID ?? context.widgetID
    let interaction = context.interaction
    interaction.textSelection.layoutRegistry.register(id, layout: self)
    guard !context.focusLeafClaimed, !context.navigationIgnored else { return }
    interaction.registerFocusTargets(context.focusTargets, id: id)
    _ = interaction.registerTextInput(
      id: id, rect: rect, text: { text.content }, onChange: { _ in },
      pointerOffset: { point, _ in hitTest(point: point) ?? 0 },
      verticalOffset: { verticalOffset($0, direction: $1) }, readOnly: true)
  }

  @MainActor func paint(text: Text, context: BlockContext, into list: inout DrawList) {
    let id = text.selectionID ?? context.widgetID
    let interaction = context.interaction
    let acceptsInput = !context.focusLeafClaimed && !context.navigationIgnored
    let editing = acceptsInput && interaction.editingLeaf == id
    let caret = editing ? interaction.caretOffset : nil
    var range = editing ? interaction.textSelectionRange : nil
    if acceptsInput { FocusHighlight.paint(for: id, into: &list, in: rect, context: context) }
    if range == nil, let selection = interaction.textSelection.selection(for: id) {
      range = selection.from..<selection.to
    }
    let layout = layout
    func drawText(color: Color, into list: inout DrawList) {
      for (row, line) in layout.lines.enumerated() {
        list.text(
          line.text, at: Point(x: rect.minX, y: rect.minY + Float(row) * lineHeight),
          color: color, scale: scale)
      }
    }
    drawText(color: text.color, into: &list)
    if let range, !range.isEmpty {
      for (row, line) in layout.lines.enumerated() {
        let lower = max(line.range.lowerBound, range.lowerBound)
        let upper = min(line.range.upperBound, range.upperBound)
        guard lower < upper else { continue }
        let highlight = Rect(
          x: rect.minX + Float(lower - line.range.lowerBound) * cellWidth,
          y: rect.minY + Float(row) * lineHeight,
          width: Float(upper - lower) * cellWidth, height: lineHeight)
        list.fillRect(highlight, color: context.theme.focus.selectionBackground)
        list.pushClip(highlight)
        drawText(color: context.theme.focus.selectionForeground, into: &list)
        list.popClip()
      }
    } else if let caret {
      let point = position(at: caret)
      let caretRect = Rect(x: point.x, y: point.y, width: 1, height: lineHeight)
      context.animateCaret(into: &list, readOnly: true) { list, _ in
        if context.caretVisible { list.fillRect(caretRect, color: context.theme.focus.ring) }
      }
    }
  }
}
