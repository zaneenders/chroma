public struct Text: LifecycleElement {
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

  public func prepareInteraction(in rect: Rect, context: BlockContext) {
    if isSelectable { selectionLayout(in: rect, context: context).prepare(text: self, context: context) }
  }
  public func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    if isSelectable {
      selectionLayout(in: rect, context: context).paint(text: self, context: context, into: &drawList)
    } else {
      drawText(into: &drawList, in: rect, color: color, scale: scale * context.textScale, context: context)
    }
  }
  @MainActor private func selectionLayout(in rect: Rect, context: BlockContext) -> PlainTextLayout {
    let effectiveScale = scale * context.textScale
    return PlainTextLayout(text: content, rect: rect,
      cellWidth: context.fontMetrics.cellAdvance * effectiveScale,
      lineHeight: context.fontMetrics.lineAdvance * effectiveScale,
      scale: effectiveScale, columns: columns(width: rect.size.width, context: context))
  }
  @MainActor private func drawText(
    into drawList: inout DrawList, in rect: Rect, color: Color, scale: Float, context: BlockContext
  ) {
    for (row, line) in TextLayout(content, columns: columns(width: rect.size.width, context: context)).lines
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
