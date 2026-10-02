public struct TextEditor: PaintableBlock {
  public var placeholder: String
  public var fontScale: Float
  public var lineLimits: ClosedRange<Int>
  public var singleLine: Bool
  public var padding: Float
  public var style: TextEditorStyle?
  public let getText: @MainActor () -> String
  public let onChange: @MainActor (String) -> Void
  public let onSubmit: (@MainActor (String) -> Void)?
  public let onEndEditing: (@MainActor () -> CommandResult)?
  public let onTextEvent: (@MainActor (TextEditEvent, String) -> String?)?

  public init(
    _ placeholder: String = "", fontScale: Float = 1, lineLimits: ClosedRange<Int> = 1...6,
    padding: Float = 8, style: TextEditorStyle? = nil, singleLine: Bool = false,
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
    self.singleLine = singleLine
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

  private func columns(width: Float, cellWidth: Float) -> Int? {
    let columns =
      cellWidth.isFinite && cellWidth > 0 && width.isFinite
      ? Int(min(Float(Int32.max), max(1, (width - 2 * padding) / cellWidth))) : nil
    return columns
  }

  public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    sizeThatFits(proposal, context: context, preparation: TextLayoutPreparation())
  }

  @MainActor private func sizeThatFits(
    _ proposal: Size, context: BlockContext, preparation: TextLayoutPreparation
  ) -> Size {
    let scale = fontScale * context.textScale
    if singleLine {
      return Size(width: proposal.width, height: context.fontMetrics.glyphHeight * scale + 2 * padding + 2)
    }
    let layout = preparation.resolve(
      getText(), columns: columns(width: proposal.width, cellWidth: context.fontMetrics.cellAdvance * scale)
    ).layout
    let count = min(lineLimits.upperBound, max(lineLimits.lowerBound, layout.lines.count))
    return Size(width: proposal.width, height: Float(count) * context.fontMetrics.lineAdvance * scale + 2 * padding)
  }

  /// Immutable geometry for the current operation. Its text shaping is shared with
  /// measurement and painting; installed handlers retain this exact update snapshot.
  private struct PreparedText {
    let text: String
    let scale: Float
    let cellWidth: Float
    let lineHeight: Float
    let snapshot: TextLayoutSnapshot
    var layout: TextLayout { snapshot.layout }
    let inner: Rect
    let visibleCount: Int
    let singleLine: Bool

    func horizontalOffset(_ caret: Int?) -> Float {
      guard singleLine, let caret else { return 0 }
      return min(0, inner.size.width - cellWidth - Float(caret) * cellWidth)
    }

    func firstRow(_ caret: Int?) -> Int {
      guard let caret else { return 0 }
      return max(0, min(layout.lines.count - visibleCount, layout.row(containing: caret) - visibleCount + 1))
    }
  }

  @MainActor private func prepareText(
    in rect: Rect, context: BlockContext, preparation: TextLayoutPreparation
  ) -> PreparedText? {
    let text = getText()
    let scale = fontScale * context.textScale
    let cellWidth = context.fontMetrics.cellAdvance * scale
    let lineHeight = context.fontMetrics.lineAdvance * scale
    guard cellWidth.isFinite, cellWidth > 0, lineHeight.isFinite, lineHeight > 0 else { return nil }
    let snapshot = preparation.resolve(
      text, columns: columns(width: singleLine ? .infinity : rect.size.width, cellWidth: cellWidth))
    let inner = Rect(
      x: rect.minX + padding, y: rect.minY + padding + (singleLine ? 1 : 0),
      width: max(0, rect.size.width - padding * 2),
      height: singleLine ? context.fontMetrics.glyphHeight * scale : max(0, rect.size.height - padding * 2))
    let visibleCount = singleLine ? 1 : max(1, Int(inner.size.height / lineHeight))
    return PreparedText(
      text: text, scale: scale, cellWidth: cellWidth, lineHeight: lineHeight,
      snapshot: snapshot, inner: inner, visibleCount: visibleCount, singleLine: singleLine)
  }

  @MainActor private func register(
    _ prepared: PreparedText, in rect: Rect, context: BlockContext
  ) {
    let interaction = context.interaction
    let viewportRow =
      interaction.textDragViewportRow
      ?? prepared.firstRow(
        interaction.editingLeaf == context.widgetID
          ? interaction.caretOffset : nil)
    if !singleLine && interaction.isDragging, interaction.textDragViewportRow != nil {
      if interaction.dragCurrent.y >= prepared.inner.maxY {
        interaction.textDragViewportRow = min(
          max(0, prepared.layout.lines.count - prepared.visibleCount), viewportRow + 1)
      } else if interaction.dragCurrent.y < prepared.inner.minY {
        interaction.textDragViewportRow = max(0, viewportRow - 1)
      }
    }
    _ = context.textInputState(
      in: rect, text: getText, onChange: onChange, onSubmit: onSubmit,
      onEndEditing: onEndEditing,
      onTextEvent: onTextEvent,
      pointerOffset: { [weak interaction] point, caret in
        if !singleLine, let interaction, interaction.isProcessingDrag, interaction.textDragViewportRow == nil {
          interaction.textDragViewportRow = viewportRow
        }
        return prepared.layout.offset(
          row: singleLine
            ? 0
            : (interaction?.textDragViewportRow ?? prepared.firstRow(caret))
              + Int(((point.y - prepared.inner.minY) / prepared.lineHeight).rounded(.down)),
          column: Int(
            ((point.x - prepared.inner.minX - prepared.horizontalOffset(caret)) / prepared.cellWidth)
              .rounded(.toNearestOrAwayFromZero)))
      },
      verticalOffset: { prepared.layout.verticalOffset($0, direction: $1) },
      submitInsertsNewline: !singleLine && onSubmit == nil)
  }

  public func register(in rect: Rect, context: BlockContext) {
    guard
      let prepared = prepareText(
        in: rect, context: context, preparation: TextLayoutPreparation())
    else { return }
    register(prepared, in: rect, context: context)
  }

  public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    guard
      let prepared = prepareText(
        in: rect, context: context, preparation: TextLayoutPreparation())
    else { return }
    register(prepared, in: rect, context: context)
    paint(prepared, into: &drawList, in: rect, context: context)
  }

  public func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    guard
      let prepared = prepareText(
        in: rect, context: context, preparation: TextLayoutPreparation())
    else { return }
    paint(prepared, into: &drawList, in: rect, context: context)
  }

  @MainActor private func paint(
    _ prepared: PreparedText, into drawList: inout DrawList, in rect: Rect, context: BlockContext
  ) {
    var state = context.textInputVisualState()
    // Direct paint may follow a binding mutation without an update. Keep visual offsets
    // safe locally; only registration is allowed to reconcile the actual editing state.
    if let caret = state.caretOffset {
      state.caretOffset = max(0, min(prepared.layout.characterCount, caret))
    }
    if let range = state.selectionRange {
      let lower = max(0, min(prepared.layout.characterCount, range.lowerBound))
      let upper = max(lower, min(prepared.layout.characterCount, range.upperBound))
      state.selectionRange = lower == upper ? nil : lower..<upper
    }
    let text = prepared.text
    let scale = prepared.scale
    let cellWidth = prepared.cellWidth
    let lineHeight = prepared.lineHeight
    let layout = prepared.layout
    let inner = prepared.inner
    let visibleCount = prepared.visibleCount
    let style = style ?? context.theme.textEditor
    drawList.textInputBackground(in: rect, style: style, editing: state.editing)
    if state.focused {
      drawList.strokeRoundedRect(
        rect, radius: style.cornerRadius, width: 2, color: context.theme.focus.ring)
    }
    drawList.pushClip(inner)
    defer { drawList.popClip() }
    if text.isEmpty && !state.editing {
      drawList.text(placeholder, at: inner.origin, color: style.placeholder, scale: scale)
      return
    }
    let first =
      context.interaction.isProcessingDrag
      ? max(
        0,
        min(
          max(0, layout.lines.count - visibleCount),
          context.interaction.textDragViewportRow ?? prepared.firstRow(state.caretOffset)))
      : prepared.firstRow(state.caretOffset)
    for index in first..<min(layout.lines.count, first + visibleCount) {
      let line = layout.lines[index]
      let origin = Point(
        x: inner.minX + prepared.horizontalOffset(state.caretOffset),
        y: inner.minY + Float(index - first) * lineHeight)
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

    if let caret = state.caretOffset, state.selectionRange == nil {
      let row = layout.row(containing: caret)
      let caretRect = Rect(
        x: inner.minX + prepared.horizontalOffset(state.caretOffset)
          + Float(caret - layout.lines[row].range.lowerBound) * cellWidth,
        y: inner.minY + Float(row - first) * lineHeight, width: max(1, scale), height: lineHeight)
      drawList.fillRect(caretRect, color: style.caret)
    }
  }
}

extension TextEditor: LayoutPreparingBlock {
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    let preparation = TextLayoutPreparation()
    // Registration commits this operation's text and geometry. Its matching paint
    // does not read the application binding again, so editing and pixels cannot use
    // different versions. A later input/update resolves a fresh operation.
    var registered: (rect: Rect, text: PreparedText)?
    return BlockEngine.Resolved(
      expandsHorizontally: { true }, expandsVertically: { false },
      measure: { proposal in sizeThatFits(proposal, context: context, preparation: preparation) },
      register: { rect in
        registered = nil
        guard let prepared = prepareText(in: rect, context: context, preparation: preparation) else { return }
        registered = (rect, prepared)
        register(prepared, in: rect, context: context)
      },
      paint: { list, rect in
        if let registered, registered.rect == rect {
          paint(registered.text, into: &list, in: rect, context: context)
          return
        }
        guard let prepared = prepareText(in: rect, context: context, preparation: preparation) else { return }
        paint(prepared, into: &list, in: rect, context: context)
      },
      draw: { list, rect in
        guard let prepared = prepareText(in: rect, context: context, preparation: preparation) else { return }
        register(prepared, in: rect, context: context)
        paint(prepared, into: &list, in: rect, context: context)
      })
  }
}
