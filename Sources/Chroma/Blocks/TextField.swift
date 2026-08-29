import Foundation

public struct TextField: PrimitiveBlock {
  public var id: WidgetID
  public var placeholder: String
  public var getText: () -> String
  public var onChange: (String) -> Void
  public var onSubmit: ((String) -> Void)?
  public var fontScale: Float
  public var padding: Float
  public var style: TextFieldStyle?

  public init(
    _ placeholder: String = "",
    id: WidgetID,
    fontScale: Float = 1,
    padding: Float = 8,
    style: TextFieldStyle? = nil,
    text getText: @escaping () -> String,
    onChange: @escaping (String) -> Void,
    onSubmit: ((String) -> Void)? = nil
  ) {
    self.id = id
    self.placeholder = placeholder
    self.getText = getText
    self.onChange = onChange
    self.onSubmit = onSubmit
    self.fontScale = fontScale
    self.padding = padding
    self.style = style
  }

  @MainActor public var expandsHorizontally: Bool { true }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    let metrics = context.fontMetrics
    let scale = fontScale * context.textScale
    return Size(
      width: proposal.width,
      height: metrics.glyphHeight * scale + 2 * padding + 2
    )
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let metrics = context.fontMetrics
    let scale = fontScale * context.textScale
    let style = style ?? context.theme.textField
    let cellWidth = metrics.cellAdvance * scale
    let textOriginX = rect.minX + padding
    let innerWidth = max(0, rect.size.width - 2 * padding)
    let viewportOffset: (Int?) -> Float = { caret in
      guard let caret, cellWidth > 0, cellWidth.isFinite else { return 0 }
      let caretX = Float(caret) * cellWidth
      var offset: Float = 0
      if caretX > innerWidth - cellWidth {
        offset = innerWidth - cellWidth - caretX
      }
      if caretX + offset < 0 {
        offset = -caretX
      }
      return min(0, offset)
    }
    let state = context.textInputState(
      id: id, in: rect, text: getText(), onChange: onChange, onSubmit: onSubmit,
      pointerOffset: { point, viewportCaret in
        guard cellWidth > 0, cellWidth.isFinite else { return 0 }
        return Int(
          ((point.x - textOriginX - viewportOffset(viewportCaret)) / cellWidth)
            .rounded(.toNearestOrAwayFromZero))
      })

    drawList.fillRoundedRect(
      rect,
      radius: style.cornerRadius,
      color: state.editing ? style.editingBackground : state.hovered ? style.hoveredBackground : style.idleBackground)
    drawList.strokeRoundedRect(
      rect,
      radius: style.cornerRadius,
      width: style.borderWidth,
      color: state.editing ? style.editingBorder : style.border)

    let inner = Rect(
      x: rect.minX + padding,
      y: rect.minY + padding + 1,
      width: innerWidth,
      height: metrics.glyphHeight * scale)

    let textOffset = viewportOffset(state.caretOffset)

    drawList.pushClip(inner)
    let text = getText()
    if text.isEmpty && !state.editing {
      drawList.text(placeholder, at: inner.origin, color: style.placeholder, scale: scale)
    } else if state.editing, let selection = state.selectionRange {
      let selectionRect = Rect(
        x: inner.minX + textOffset + Float(selection.lowerBound) * cellWidth,
        y: inner.minY,
        width: Float(selection.count) * cellWidth,
        height: inner.size.height)
      drawList.fillRect(selectionRect, color: context.theme.focus.selectionBackground)
      drawList.text(
        text,
        at: Point(x: inner.minX + textOffset, y: inner.minY),
        color: style.foreground,
        scale: scale)
      let selected = String(Array(text)[selection])
      drawList.pushClip(selectionRect)
      drawList.text(
        selected,
        at: Point(
          x: inner.minX + textOffset + Float(selection.lowerBound) * cellWidth,
          y: inner.minY),
        color: context.theme.focus.selectionForeground,
        scale: scale)
      drawList.popClip()
    } else {
      drawList.text(
        text,
        at: Point(x: inner.minX + textOffset, y: inner.minY),
        color: style.foreground,
        scale: scale)
    }
    if let caret = state.caretOffset, state.selectionRange == nil,
      Self.caretVisible
    {
      drawList.fillRect(
        Rect(
          x: (inner.minX + textOffset + Float(caret) * cellWidth).rounded(),
          y: inner.minY - 1,
          width: max(1, scale),
          height: inner.size.height + 2),
        color: style.caret)
    }
    drawList.popClip()
  }

  private static var caretVisible: Bool {
    Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) < 0.72
  }
}
