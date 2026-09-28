public struct TextField: PrimitiveBlock {
  var id: WidgetID?
  public var placeholder: String
  public var getText: @MainActor () -> String
  public var onChange: @MainActor (String) -> Void
  public var onSubmit: (@MainActor (String) -> Void)?
  public var onEndEditing: (@MainActor () -> CommandResult)?
  public var onTextEvent: (@MainActor (TextEditEvent, String) -> String?)?
  public var fontScale: Float
  public var padding: Float
  public var style: TextFieldStyle?

  init(
    _ placeholder: String = "",
    id: WidgetID?,
    fontScale: Float = 1,
    padding: Float = 8,
    style: TextFieldStyle? = nil,
    text getText: @escaping @MainActor () -> String,
    onChange: @escaping @MainActor (String) -> Void,
    onSubmit: (@MainActor (String) -> Void)? = nil,
    onEndEditing: (@MainActor () -> CommandResult)? = nil,
    onTextEvent: (@MainActor (TextEditEvent, String) -> String?)? = nil
  ) {
    self.id = id
    self.placeholder = placeholder
    self.getText = getText
    self.onChange = onChange
    self.onSubmit = onSubmit
    self.onEndEditing = onEndEditing
    self.onTextEvent = onTextEvent
    self.fontScale = fontScale
    self.padding = padding
    self.style = style
  }

  public init(
    _ placeholder: String = "",
    fontScale: Float = 1,
    padding: Float = 8,
    style: TextFieldStyle? = nil,
    text getText: @escaping @MainActor () -> String,
    onChange: @escaping @MainActor (String) -> Void,
    onSubmit: (@MainActor (String) -> Void)? = nil,
    onEndEditing: (@MainActor () -> CommandResult)? = nil,
    onTextEvent: (@MainActor (TextEditEvent, String) -> String?)? = nil
  ) {
    self.init(
      placeholder, id: nil, fontScale: fontScale, padding: padding, style: style, text: getText, onChange: onChange,
      onSubmit: onSubmit, onEndEditing: onEndEditing, onTextEvent: onTextEvent)
  }

  public var focusRule: FocusRule { .control }

  @MainActor public var expandsHorizontally: Bool { true }

  @MainActor public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    let metrics = context.fontMetrics
    let scale = fontScale * context.textScale
    return Size(
      width: proposal.width,
      height: metrics.glyphHeight * scale + 2 * padding + 2
    )
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    let id = id ?? context.widgetID
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
      id: id, in: rect, text: getText, onChange: onChange, onSubmit: onSubmit,
      onEndEditing: onEndEditing, onTextEvent: onTextEvent,
      pointerOffset: { point, viewportCaret in
        guard cellWidth > 0, cellWidth.isFinite else { return 0 }
        return Int(
          ((point.x - textOriginX - viewportOffset(viewportCaret)) / cellWidth)
            .rounded(.toNearestOrAwayFromZero))
      })

    drawList.textInputBackground(
      in: rect, style: style, editing: state.editing,
      hover: state.phase == .hovered ? HoverStyle.standardTint(in: context.theme) : nil)

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
    } else {
      let selection = state.editing ? state.selectionRange : nil
      drawList.textInputLine(
        text, at: Point(x: inner.minX + textOffset, y: inner.minY), scale: scale,
        foreground: style.foreground,
        selection: selection.map {
          Rect(
            x: inner.minX + textOffset + Float($0.lowerBound) * cellWidth,
            y: inner.minY, width: Float($0.count) * cellWidth, height: inner.size.height)
        }, theme: context.theme.focus)
    }
    if let caret = state.caretOffset, state.selectionRange == nil,
      context.caretVisible
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

}
