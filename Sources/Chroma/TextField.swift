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
    return Size(
      width: proposal.width,
      height: metrics.glyphHeight * fontScale + 2 * padding + 2
    )
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let metrics = context.fontMetrics
    let style = style ?? context.theme.textField
    let state = context.textInputState(
      id: id, in: rect, text: getText(), onChange: onChange, onSubmit: onSubmit)

    drawList.fillRect(
      rect,
      color: state.editing ? style.editingBackground : state.hovered ? style.hoveredBackground : style.idleBackground)
    drawList.strokeRect(rect, width: 1, color: state.editing ? style.editingBorder : style.border)

    let inner = Rect(
      x: rect.minX + padding,
      y: rect.minY + padding + 1,
      width: max(0, rect.size.width - 2 * padding),
      height: metrics.glyphHeight * fontScale)
    let cellWidth = metrics.cellAdvance * fontScale

    var textOffset: Float = 0
    if let caret = state.caretOffset {
      let caretX = Float(caret) * cellWidth
      if caretX + textOffset > inner.size.width - cellWidth {
        textOffset = inner.size.width - cellWidth - caretX
      }
      if caretX + textOffset < 0 {
        textOffset = -caretX
      }
      textOffset = min(0, textOffset)
    }

    drawList.pushClip(inner)
    let text = getText()
    if text.isEmpty && !state.editing {
      drawList.text(placeholder, at: inner.origin, color: style.placeholder, scale: fontScale)
    } else {
      drawList.text(
        text,
        at: Point(x: inner.minX + textOffset, y: inner.minY),
        color: style.foreground,
        scale: fontScale)
    }
    if let caret = state.caretOffset, Self.caretVisible {
      drawList.fillRect(
        Rect(
          x: (inner.minX + textOffset + Float(caret) * cellWidth).rounded(),
          y: inner.minY - 1,
          width: max(1, fontScale),
          height: inner.size.height + 2),
        color: style.caret)
    }
    drawList.popClip()
  }

  private static var caretVisible: Bool {
    Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) < 0.72
  }
}
