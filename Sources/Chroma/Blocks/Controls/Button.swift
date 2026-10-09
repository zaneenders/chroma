public struct Button: Block {
  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    buffer.button(self, context: context)
  }

  public var label: String
  var id: WidgetID?
  public let action: @MainActor () -> Void
  public var role: ActionRole
  public var fontScale: Float
  public var style: ButtonStyle?
  public var padding: EdgeInsets

  var focusRule: FocusRule { .control }

  init(
    _ label: String,
    id: WidgetID?,
    role: ActionRole = .normal,
    fontScale: Float = 1,
    style: ButtonStyle? = nil,
    padding: EdgeInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16),
    action: @escaping @MainActor () -> Void
  ) {
    self.label = label
    self.id = id
    self.action = action
    self.role = role
    self.fontScale = fontScale
    self.style = style
    self.padding = padding
  }

  public init(
    _ label: String,
    role: ActionRole = .normal,
    fontScale: Float = 1,
    style: ButtonStyle? = nil,
    padding: EdgeInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16),
    action: @escaping @MainActor () -> Void
  ) {
    self.init(label, id: nil, role: role, fontScale: fontScale, style: style, padding: padding, action: action)
  }

  @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    let textSize = context.fontMetrics.measure(label, scale: fontScale * context.textScale)
    return Size(
      width: textSize.width + padding.leading + padding.trailing,
      height: textSize.height + padding.top + padding.bottom)
  }

  @MainActor func register(in rect: Rect, context: BlockContext) {
    _ = context.buttonState(id: id ?? context.widgetID, in: rect, role: role, action: action)
  }

  @MainActor func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    let style = style ?? context.theme.button
    let state = context.buttonVisualState(id: id ?? context.widgetID)

    let background: Color
    switch state.phase {
    case .idle, .hovered: background = style.idleBackground
    case .pressed: background = style.pressedBackground
    }
    drawList.fillRoundedRect(rect, radius: style.cornerRadius, color: background)
    if state.phase == .hovered {
      drawList.fillRoundedRect(
        rect, radius: style.cornerRadius, color: HoverStyle.standardTint(in: context.theme))
    }
    drawList.strokeRoundedRect(
      rect, radius: style.cornerRadius, width: style.borderWidth, color: style.border)
    drawList.text(
      label,
      at: Point(x: rect.minX + padding.leading, y: rect.minY + padding.top),
      color: style.foreground,
      scale: fontScale * context.textScale)
  }
}
