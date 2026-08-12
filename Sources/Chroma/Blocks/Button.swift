public struct Button: PrimitiveBlock {
  public var label: String
  public var id: WidgetID
  public var action: () -> Void
  public var role: ActionRole
  public var fontScale: Float
  public var style: ButtonStyle?
  public var padding: EdgeInsets

  public init(
    _ label: String,
    id: WidgetID,
    role: ActionRole = .normal,
    fontScale: Float = 1,
    style: ButtonStyle? = nil,
    padding: EdgeInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16),
    action: @escaping () -> Void
  ) {
    self.label = label
    self.id = id
    self.action = action
    self.role = role
    self.fontScale = fontScale
    self.style = style
    self.padding = padding
  }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    let textSize = context.fontMetrics.measure(label, scale: fontScale * context.textScale)
    return Size(
      width: textSize.width + padding.leading + padding.trailing,
      height: textSize.height + padding.top + padding.bottom)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let style = style ?? context.theme.button
    let state = context.buttonState(id: id, in: rect, role: role) { action() }
    if state.clicked { action() }

    let background: Color
    switch state.phase {
    case .idle: background = style.idleBackground
    case .hovered: background = style.hoveredBackground
    case .pressed: background = style.pressedBackground
    }
    drawList.fillRoundedRect(rect, radius: style.cornerRadius, color: background)
    drawList.strokeRoundedRect(
      rect, radius: style.cornerRadius, width: style.borderWidth, color: style.border)
    drawList.text(
      label,
      at: Point(x: rect.minX + padding.leading, y: rect.minY + padding.top),
      color: style.foreground,
      scale: fontScale * context.textScale)
  }
}
