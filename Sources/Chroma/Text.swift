public struct Text: PrimitiveBlock {
  public var content: String
  public var color: Color
  public var scale: Float
  public var isSelectable: Bool = false
  public var selectionID: WidgetID?

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

  public func selectable(_ id: WidgetID? = nil) -> Text {
    var copy = self
    copy.isSelectable = true
    copy.selectionID = id ?? WidgetID("text-select-\\(content.hashValue)")
    return copy
  }

  public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    context.interaction.fontMetrics.measure(content, scale: scale)
  }

  public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    if isSelectable, let id = selectionID {
      let interaction = context.interaction
      let metrics = interaction.fontMetrics
      let cellWidth = metrics.cellAdvance * scale
      let lineHeight = metrics.lineAdvance * scale
      let layout = PlainTextLayout(
        text: content, rect: rect, cellWidth: cellWidth,
        lineHeight: lineHeight, scale: scale)
      interaction.textSelection.layoutRegistry.register(id, layout: layout)

      if let sel = interaction.textSelection.selection(for: layout) {
        let selX = rect.minX + Float(sel.from) * cellWidth
        let selW = Float(sel.to - sel.from) * cellWidth
        drawList.fillRect(
          Rect(x: selX, y: rect.minY, width: selW, height: lineHeight),
          color: Color(r: 0.3, g: 0.6, b: 1.0, a: 0.5))

        let prefix = content.prefix(sel.from)
        if !prefix.isEmpty {
          drawList.text(
            String(prefix), at: rect.origin, color: color, scale: scale)
        }
        let selected = content.dropFirst(sel.from).prefix(sel.to - sel.from)
        if !selected.isEmpty {
          let selOrigin = Point(x: rect.minX + Float(sel.from) * cellWidth, y: rect.minY)
          drawList.text(
            String(selected), at: selOrigin,
            color: Color(r: 1 - color.r, g: 1 - color.g, b: 1 - color.b, a: 1),
            scale: scale)
        }
        let suffix = content.dropFirst(sel.to)
        if !suffix.isEmpty {
          let suffixOrigin = Point(x: rect.minX + Float(sel.to) * cellWidth, y: rect.minY)
          drawList.text(
            String(suffix), at: suffixOrigin, color: color, scale: scale)
        }
        return
      }
    }
    drawList.text(content, at: rect.origin, color: color, scale: scale)
  }
}
