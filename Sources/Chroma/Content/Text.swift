public struct Text {
  public var content: String
  public var color: Color
  public var scale: Float
  public var isSelectable: Bool = false
  public var wraps = false
  var selectionID: WidgetID?

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

  @MainActor private func columns(width: Float, context: LayoutContext) -> Int? {
    let cell = context.fontMetrics.cellAdvance * scale * context.textScale
    guard wraps, width.isFinite, cell.isFinite, cell > 0 else { return nil }
    return Int(min(Float(Int32.max), max(1, width / cell)))
  }

  @MainActor func sizeThatFits(_ proposal: Size, context: LayoutContext) -> Size {
    sizeThatFits(proposal, context: context, preparation: context.interaction.textLayouts)
  }

  @MainActor private func sizeThatFits(
    _ proposal: Size, context: LayoutContext, preparation: TextLayoutPreparation
  ) -> Size {
    guard wraps else {
      return context.fontMetrics.measure(content, scale: scale * context.textScale)
    }
    let layout = preparation.resolve(content, columns: columns(width: proposal.width, context: context)).layout
    return Size(
      width: proposal.width,
      height: Float(layout.lines.count) * context.fontMetrics.lineAdvance * scale * context.textScale)
  }

  @MainActor func register(in rect: Rect, context: LayoutContext) {
    if isSelectable {
      registerSelection(
        prepareText(in: rect, context: context, preparation: context.interaction.textLayouts), context: context)
    } else if context.interaction.builderStack.last != nil, !context.focusLeafClaimed, !context.navigationIgnored {
      context.registerFocusable(in: rect)
    }
  }

  @MainActor private func prepareText(
    in rect: Rect, context: LayoutContext, preparation: TextLayoutPreparation
  ) -> PlainTextLayout {
    let effectiveScale = scale * context.textScale
    let metrics = context.fontMetrics
    let columns = columns(width: rect.size.width, context: context)
    return PlainTextLayout(
      rect: rect, cellWidth: metrics.cellAdvance * effectiveScale,
      lineHeight: metrics.lineAdvance * effectiveScale,
      snapshot: preparation.resolve(content, columns: columns))
  }

  @MainActor private func registerSelection(_ layout: PlainTextLayout, context: LayoutContext) {
    let id = selectionID ?? context.widgetID
    let interaction = context.interaction
    if !context.navigationIgnored {
      interaction.registerFocusTargets(context.focusTargets, id: id)
    }
    _ = interaction.registerTextInput(
      id: id, rect: layout.rect, text: { content }, onChange: { _ in },
      pointerOffset: { point, _ in layout.selectionOffset(at: point) },
      verticalOffset: { layout.verticalOffset($0, direction: $1) },
      navigationIgnored: context.navigationIgnored, readOnly: true)
  }

  @MainActor func paint(into drawList: inout DrawList, in rect: Rect, context: LayoutContext) {
    if isSelectable, !context.focusLeafClaimed, !context.navigationIgnored {
      context.paintFocusHighlight(for: selectionID ?? context.widgetID, in: rect, into: &drawList)
    }
    if !wraps, !isSelectable {
      drawText(
        into: &drawList, in: rect, color: color, scale: scale * context.textScale,
        context: context, layout: context.interaction.textLayouts.resolve(content, columns: nil).layout)
    } else {
      paint(
        prepareText(in: rect, context: context, preparation: context.interaction.textLayouts),
        into: &drawList, in: rect, context: context)
    }
    if !isSelectable, !context.focusLeafClaimed, !context.navigationIgnored {
      context.paintFocusHighlight(for: selectionID ?? context.widgetID, in: rect, into: &drawList)
    }
  }

  @MainActor private func paint(
    _ layout: PlainTextLayout, into drawList: inout DrawList, in rect: Rect, context: LayoutContext
  ) {
    let effectiveScale = scale * context.textScale
    if isSelectable {
      let cellWidth = layout.cellWidth
      let lineHeight = layout.lineHeight
      let state = context.textInputVisualState(id: selectionID ?? context.widgetID)
      let range = state.selectionRange
      let caret = context.navigationIgnored ? nil : state.caretOffset
      drawText(
        into: &drawList, in: rect, color: color, scale: effectiveScale, context: context, layout: layout.layout)
      if let range, !range.isEmpty {
        for (row, line) in layout.layout.lines.enumerated() {
          let start = line.range.lowerBound
          let end = line.range.upperBound
          let lower = max(start, range.lowerBound)
          let upper = min(end, range.upperBound)
          if lower < upper {
            let origin = Point(x: rect.minX, y: rect.minY + Float(row) * lineHeight)
            let highlight = Rect(
              x: origin.x + Float(lower - start) * cellWidth, y: origin.y,
              width: Float(upper - lower) * cellWidth, height: lineHeight)
            drawList.fillRect(highlight, color: context.theme.focus.selectionBackground)
            drawList.pushClip(highlight)
            // Clipping happens in the backend, after commands have been generated.
            // Redraw only this row, rather than the entire layout for every selection.
            drawList.text(
              line.text, at: origin, color: context.theme.focus.selectionForeground, scale: effectiveScale)
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
    drawText(
      into: &drawList, in: rect, color: color, scale: effectiveScale, context: context, layout: layout.layout)
  }
  @MainActor private func drawText(
    into drawList: inout DrawList, in rect: Rect, color: Color, scale: Float, context: LayoutContext,
    layout: TextLayout
  ) {
    for (row, line) in layout.lines.enumerated() {
      drawList.text(
        line.text,
        at: Point(
          x: rect.minX,
          y: rect.minY + Float(row) * context.fontMetrics.lineAdvance * scale), color: color, scale: scale)
    }
  }

}
