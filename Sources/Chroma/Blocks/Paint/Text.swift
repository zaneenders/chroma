public struct Text: PrimitiveBlock {
  public var content: String
  public var color: Color
  public var scale: Float
  public var isSelectable: Bool = false
  public var wraps = false
  var selectionID: WidgetID?

  public var focusRule: FocusRule { .standard }

  public init(_ content: String) {
    self.content = content
    self.color = .white
    self.scale = 1
  }

  public func foregroundColor(_ color: Color) -> Text {
    var copy = self
    copy.color = color
    return copy
  }

  public func fontScale(_ scale: Float) -> Text {
    var copy = self
    copy.scale = scale
    return copy
  }

  public func selectable() -> Text {
    selectable(nil)
  }

  func selectable(_ id: WidgetID?) -> Text {
    var copy = self
    copy.isSelectable = true
    copy.selectionID = id
    return copy
  }

  public func wrapping(_ enabled: Bool = true) -> Text {
    var copy = self
    copy.wraps = enabled
    return copy
  }

  @MainActor private func columns(width: Float, context: BlockContext) -> Int? {
    let cell = context.fontMetrics.cellAdvance * scale * context.textScale
    guard wraps, width.isFinite, cell.isFinite, cell > 0 else { return nil }
    return Int(min(Float(Int32.max), max(1, width / cell)))
  }

  public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    guard wraps else {
      return context.fontMetrics.measure(content, scale: scale * context.textScale)
    }
    let layout = TextLayout(content, columns: columns(width: proposal.width, context: context))
    return Size(
      width: proposal.width,
      height: Float(layout.lines.count) * context.fontMetrics.lineAdvance * scale * context.textScale)
  }

  public func register(in rect: Rect, context: BlockContext) {
    if isSelectable { _ = registerSelection(in: rect, context: context) }
  }

  @MainActor private func registerSelection(
    in rect: Rect, context: BlockContext
  ) -> (layout: PlainTextLayout, range: Range<Int>?, caret: Int?) {
    let effectiveScale = scale * context.textScale
    let id = selectionID ?? context.widgetID
    let interaction = context.interaction
    let metrics = interaction.fontMetrics
    let cellWidth = metrics.cellAdvance * effectiveScale
    let lineHeight = metrics.lineAdvance * effectiveScale
    let layout = PlainTextLayout(
      text: content, rect: rect, cellWidth: cellWidth,
      lineHeight: lineHeight, scale: effectiveScale, columns: columns(width: rect.size.width, context: context))
    interaction.textSelection.layoutRegistry.register(id, layout: layout)

    var range: Range<Int>?
    var caret: Int?
    if !context.focusLeafClaimed, !context.navigationIgnored {
      interaction.registerFocusTargets(context.focusTargets, id: id)
      let state = interaction.registerTextInput(
        id: id, rect: rect, text: { content }, onChange: { _ in },
        pointerOffset: { point, _ in layout.hitTest(point: point) ?? 0 },
        verticalOffset: { layout.verticalOffset($0, direction: $1) }, readOnly: true)
      range = state.selectionRange
      caret = state.caretOffset
    }
    if range == nil, let selection = interaction.textSelection.selection(for: id) {
      range = selection.from..<selection.to
    }
    return (layout, range, caret)
  }

  public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    let effectiveScale = scale * context.textScale
    if isSelectable {
      let registration = registerSelection(in: rect, context: context)
      let id = selectionID ?? context.widgetID
      let layout = registration.layout
      let cellWidth = layout.cellWidth
      let lineHeight = layout.lineHeight
      let range = registration.range
      let caret = registration.caret
      if !context.focusLeafClaimed, !context.navigationIgnored {
        BlockEngine.drawHighlight(for: id, into: &drawList, in: rect, context: context)
      }
      drawText(
        into: &drawList, in: rect, color: color, scale: effectiveScale, context: context, layout: layout.layout)
      if let range, !range.isEmpty {
        for line in layout.layout.lines {
          let start = line.range.lowerBound
          let end = line.range.upperBound
          let lower = max(start, range.lowerBound)
          let upper = min(end, range.upperBound)
          if lower < upper {
            let origin = layout.position(at: lower)
            let highlight = Rect(
              x: origin.x, y: origin.y,
              width: Float(upper - lower) * cellWidth, height: lineHeight)
            drawList.fillRect(highlight, color: context.theme.focus.selectionBackground)
            drawList.pushClip(highlight)
            drawText(
              into: &drawList, in: rect, color: context.theme.focus.selectionForeground, scale: effectiveScale,
              context: context, layout: layout.layout)
            drawList.popClip()
          }
        }
      } else if let caret {
        let point = layout.position(at: caret)
        let caretRect = Rect(x: point.x, y: point.y, width: 1, height: lineHeight)
        drawList.fillRect(caretRect, color: context.theme.focus.ring)
      }
      return
    }
    drawText(into: &drawList, in: rect, color: color, scale: effectiveScale, context: context)
  }
  @MainActor private func drawText(
    into drawList: inout DrawList, in rect: Rect, color: Color, scale: Float, context: BlockContext,
    layout: TextLayout? = nil
  ) {
    for (row, line) in (layout ?? TextLayout(content, columns: columns(width: rect.size.width, context: context))).lines
      .enumerated()
    {
      drawList.text(
        line.text,
        at: Point(
          x: rect.minX,
          y: rect.minY + Float(row) * context.fontMetrics.lineAdvance * scale), color: color, scale: scale)
    }
  }

}
