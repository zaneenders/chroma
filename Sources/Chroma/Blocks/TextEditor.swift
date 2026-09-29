public struct TextEditor: PrimitiveBlock {
  public var placeholder: String
  public var fontScale: Float
  public var lineLimits: ClosedRange<Int>
  public var padding: Float
  public var style: TextFieldStyle?
  public let getText: @MainActor () -> String
  public let onChange: @MainActor (String) -> Void
  public let onSubmit: (@MainActor (String) -> Void)?
  public let onEndEditing: (@MainActor () -> CommandResult)?
  public let onTextEvent: (@MainActor (TextEditEvent, String) -> String?)?

  public init(
    _ placeholder: String = "", fontScale: Float = 1, lineLimits: ClosedRange<Int> = 1...6,
    padding: Float = 8, style: TextFieldStyle? = nil,
    text: @escaping @MainActor () -> String,
    onChange: @escaping @MainActor (String) -> Void,
    onSubmit: (@MainActor (String) -> Void)? = nil,
    onEndEditing: (@MainActor () -> CommandResult)? = nil,
    onTextEvent: (@MainActor (TextEditEvent, String) -> String?)? = nil
  ) {
    precondition(lineLimits.lowerBound > 0)
    self.placeholder = placeholder
    self.fontScale = fontScale
    self.lineLimits = lineLimits
    self.padding = padding
    self.style = style
    self.getText = text
    self.onChange = onChange
    self.onSubmit = onSubmit
    self.onEndEditing = onEndEditing
    self.onTextEvent = onTextEvent
  }

  public var focusRule: FocusRule { .control }
  public var expandsHorizontally: Bool { true }

  private func layout(_ text: String, width: Float, cellWidth: Float) -> TextLayout {
    let columns =
      cellWidth.isFinite && cellWidth > 0 && width.isFinite
      ? Int(min(Float(Int32.max), max(1, (width - 2 * padding) / cellWidth))) : 1
    return TextLayout(text, columns: columns)
  }

  public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    let scale = fontScale * context.textScale
    let layout = layout(getText(), width: proposal.width, cellWidth: context.fontMetrics.cellAdvance * scale)
    let count = min(lineLimits.upperBound, max(lineLimits.lowerBound, layout.lines.count))
    return Size(width: proposal.width, height: Float(count) * context.fontMetrics.lineAdvance * scale + 2 * padding)
  }

  public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    let text = getText()
    let scale = fontScale * context.textScale
    let cellWidth = context.fontMetrics.cellAdvance * scale
    let lineHeight = context.fontMetrics.lineAdvance * scale
    guard cellWidth.isFinite, cellWidth > 0, lineHeight.isFinite, lineHeight > 0 else { return }
    let layout = layout(text, width: rect.size.width, cellWidth: cellWidth)
    let inner = Rect(
      x: rect.minX + padding, y: rect.minY + padding,
      width: max(0, rect.size.width - padding * 2), height: max(0, rect.size.height - padding * 2))
    let visibleCount = max(1, Int(inner.size.height / lineHeight))
    let firstRow: (Int?) -> Int = { caret in
      guard let caret else { return 0 }
      return max(0, min(layout.lines.count - visibleCount, layout.row(containing: caret) - visibleCount + 1))
    }
    let interaction = context.interaction
    let viewportRow = interaction.textDragViewportRow ?? firstRow(interaction.editingLeaf == context.widgetID
      ? interaction.caretOffset : nil)
    if interaction.isDragging, interaction.textDragViewportRow != nil {
      if interaction.dragCurrent.y >= inner.maxY {
        interaction.textDragViewportRow = min(layout.lines.count - visibleCount, viewportRow + 1)
      } else if interaction.dragCurrent.y < inner.minY {
        interaction.textDragViewportRow = max(0, viewportRow - 1)
      }
    }
    let state = context.textInputState(
      in: rect, text: getText, onChange: onChange, onSubmit: onSubmit,
      onEndEditing: onEndEditing,
      onTextEvent: onTextEvent,
      pointerOffset: { point, caret in
        if context.interaction.isProcessingDrag && context.interaction.textDragViewportRow == nil {
          context.interaction.textDragViewportRow = viewportRow
        }
        return layout.offset(
          row: (context.interaction.textDragViewportRow ?? firstRow(caret))
            + Int(((point.y - inner.minY) / lineHeight).rounded(.down)),
          column: Int(((point.x - inner.minX) / cellWidth).rounded(.toNearestOrAwayFromZero)))
      },
      verticalOffset: { layout.verticalOffset($0, direction: $1) },
      submitInsertsNewline: onSubmit == nil)
    let style = style ?? context.theme.textField
    drawList.textInputBackground(in: rect, style: style, editing: state.editing)
    drawList.pushClip(inner)
    defer { drawList.popClip() }
    if text.isEmpty && !state.editing {
      drawList.text(placeholder, at: inner.origin, color: style.placeholder, scale: scale)
      return
    }
    let first = context.interaction.isProcessingDrag
      ? context.interaction.textDragViewportRow ?? viewportRow : firstRow(state.caretOffset)
    for index in first..<min(layout.lines.count, first + visibleCount) {
      let line = layout.lines[index]
      let origin = Point(x: inner.minX, y: inner.minY + Float(index - first) * lineHeight)
      let selection = state.selectionRange.flatMap { selection -> Rect? in
        let lower = max(line.range.lowerBound, selection.lowerBound)
        let upper = min(line.range.upperBound, selection.upperBound)
        guard lower < upper else { return nil }
        return Rect(
          x: origin.x + Float(lower - line.range.lowerBound) * cellWidth, y: origin.y,
          width: Float(upper - lower) * cellWidth, height: lineHeight)
      }
      drawList.textInputLine(
        line.text, at: origin, scale: scale, foreground: style.foreground,
        selection: selection, theme: context.theme.focus)
    }

    if let caret = state.caretOffset, state.selectionRange == nil, context.caretVisible {
      let row = layout.row(containing: caret)
      drawList.fillRect(
        Rect(
          x: inner.minX + Float(caret - layout.lines[row].range.lowerBound) * cellWidth,
          y: inner.minY + Float(row - first) * lineHeight, width: max(1, scale), height: lineHeight),
        color: style.caret)
    }
  }
}
