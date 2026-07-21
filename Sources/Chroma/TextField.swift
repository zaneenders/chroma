import Foundation

/// A single-line text field: the framework's insert mode.
///
/// The field is a leaf of the focus tree like any interactive widget. When
/// the cursor is on it, activation — a click, or `enter` — enters insert
/// mode: the backend starts sending text instead of navigation commands, a
/// blinking caret appears, and every keystroke edits the value through
/// `onChange`. `esc` (or `return`) ends the session, as does anything that
/// moves the cursor away — a hover macro, a scroll step, another click —
/// because there is only one cursor.
///
/// The value lives in application state and is re-read every frame, like
/// everything else in the tree:
///
/// ```swift
/// TextField("your name", text: { state.name }, onChange: { state.name = $0 })
/// ```
///
/// The field expands horizontally and hugs its content vertically (one line
/// of the bitmap font plus padding). Long text scrolls horizontally to keep
/// the caret visible. Caret geometry assumes one monospace cell per
/// character, which is exact for the ASCII bitmap font.
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

  /// The field's ID defaults to its placeholder; pass `id` to disambiguate
  /// fields that share a placeholder.
  public init(
    _ placeholder: String = "",
    id: WidgetID? = nil,
    fontScale: Float = 2,
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

  @MainActor public func sizeThatFits(_ proposal: Size) -> Size {
    let metrics = FontMetrics()
    return Size(
      width: proposal.width,
      height: metrics.glyphHeight * fontScale + 2 * padding + 2  // border
    )
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect) {
    let metrics = FontMetrics()
    let state = Interaction.current.textInputBehavior(
      id: id, rect: rect, text: getText(), onChange: onChange, onSubmit: onSubmit)

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

    // Scroll long text horizontally so the caret stays inside the clip.
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

  /// The caret's blink phase: a ~1.2s cycle, visible 60% of the time.
  private static var caretVisible: Bool {
    Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) < 0.72
  }
}
