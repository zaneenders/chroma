public struct Text: PrimitiveBlock {
  public var content: String
  public var color: Color
  public var scale: Float
  public var isSelectable: Bool = false
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

  public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    context.interaction.fontMetrics.measure(
      content, scale: scale * context.textScale)
  }

  public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let effectiveScale = scale * context.textScale
    if isSelectable {
      let id = selectionID ?? context.widgetID
      let interaction = context.interaction
      let metrics = interaction.fontMetrics
      let cellWidth = metrics.cellAdvance * effectiveScale
      let lineHeight = metrics.lineAdvance * effectiveScale
      let layout = PlainTextLayout(
        text: content, rect: rect, cellWidth: cellWidth,
        lineHeight: lineHeight, scale: effectiveScale)
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
        BlockEngine.drawHighlight(for: id, into: &drawList, in: rect, context: context)
      }
      if range == nil, let selection = interaction.textSelection.selection(for: id) {
        range = selection.from..<selection.to
      }
      drawText(into: &drawList, at: rect.origin, color: color, scale: effectiveScale, context: context)
      if let range, !range.isEmpty {
        var start = 0
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
          let end = start + line.count
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
              into: &drawList, at: rect.origin, color: context.theme.focus.selectionForeground, scale: effectiveScale,
              context: context)
            drawList.popClip()
          }
          start = end + 1
        }
      } else if let caret, context.caretVisible {
        let point = layout.position(at: caret)
        drawList.fillRect(Rect(x: point.x, y: point.y, width: 1, height: lineHeight), color: context.theme.focus.ring)
      }
      return
    }
    drawText(into: &drawList, at: rect.origin, color: color, scale: effectiveScale, context: context)
  }
  @MainActor private func drawText(
    into drawList: inout DrawList, at origin: Point, color: Color, scale: Float, context: RenderContext
  ) {
    for (row, line) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
      drawList.text(
        String(line),
        at: Point(
          x: origin.x,
          y: origin.y + Float(row) * context.fontMetrics.lineAdvance * scale), color: color, scale: scale)
    }
  }

}
