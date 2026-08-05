import Foundation

public struct TextField: PrimitiveBlock {
  public var id: WidgetID
  public var placeholder: String
  public var getText: () -> String
  public var onChange: (String) -> Void
  public var onSubmit: ((String) -> Void)?
  public var fontScale: Float
  public var padding: Float
  public var textColor: Color
  public var placeholderColor: Color
  public var caretColor: Color
  public var idleColor: Color
  public var hoveredColor: Color
  public var editingColor: Color
  public var borderColor: Color
  public var editingBorderColor: Color

  public init(
    _ placeholder: String = "",
    id: WidgetID? = nil,
    fontScale: Float = 1,
    padding: Float = 8,
    textColor: Color = .white,
    placeholderColor: Color = Color(r: 0.45, g: 0.45, b: 0.55, a: 1),
    caretColor: Color = .white,
    idleColor: Color = Color(r: 0.14, g: 0.15, b: 0.22, a: 1),
    hoveredColor: Color = Color(r: 0.17, g: 0.19, b: 0.28, a: 1),
    editingColor: Color = Color(r: 0.10, g: 0.12, b: 0.20, a: 1),
    borderColor: Color = Color(r: 0.22, g: 0.22, b: 0.32, a: 1),
    editingBorderColor: Color = Color(r: 0.3, g: 0.6, b: 1.0, a: 1),
    text getText: @escaping () -> String,
    onChange: @escaping (String) -> Void,
    onSubmit: ((String) -> Void)? = nil
  ) {
    self.id = id ?? WidgetID("field:\(placeholder)")
    self.placeholder = placeholder
    self.getText = getText
    self.onChange = onChange
    self.onSubmit = onSubmit
    self.fontScale = fontScale
    self.padding = padding
    self.textColor = textColor
    self.placeholderColor = placeholderColor
    self.caretColor = caretColor
    self.idleColor = idleColor
    self.hoveredColor = hoveredColor
    self.editingColor = editingColor
    self.borderColor = borderColor
    self.editingBorderColor = editingBorderColor
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
    let state = context.textInputState(
      id: id, in: rect, text: getText(), onChange: onChange, onSubmit: onSubmit)

    drawList.fillRect(
      rect,
      color: state.editing ? editingColor : state.hovered ? hoveredColor : idleColor)
    drawList.strokeRect(rect, width: 1, color: state.editing ? editingBorderColor : borderColor)

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
      drawList.text(placeholder, at: inner.origin, color: placeholderColor, scale: fontScale)
    } else {
      drawList.text(
        text,
        at: Point(x: inner.minX + textOffset, y: inner.minY),
        color: textColor,
        scale: fontScale)
    }
    if let caret = state.caretOffset, Self.caretVisible {
      drawList.fillRect(
        Rect(
          x: (inner.minX + textOffset + Float(caret) * cellWidth).rounded(),
          y: inner.minY - 1,
          width: max(1, fontScale),
          height: inner.size.height + 2),
        color: caretColor)
    }
    drawList.popClip()
  }

  private static var caretVisible: Bool {
    Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) < 0.72
  }
}
