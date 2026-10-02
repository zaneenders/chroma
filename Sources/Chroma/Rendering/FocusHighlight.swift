@MainActor
enum FocusHighlight {
  static func paint(
    for id: WidgetID,
    into drawList: inout DrawList,
    in rect: Rect,
    context: BlockContext
  ) {
    let leafState = context.interaction.untrackedLeafState
    let pressed = leafState.pressed == id && context.interaction.input.pointerDown
    guard leafState.selected == id || leafState.hovered == id || pressed else { return }
    if context.hoverStyle == HoverStyle.none { return }
    if leafState.selected == id && !pressed && context.hoverStyle == nil {
      drawList.strokeRect(rect, width: 2, color: context.theme.focus.ring)
      return
    }
    switch context.hoverStyle ?? .standard {
    case .none:
      return
    case .tint(let color):
      drawList.fillRect(rect, color: color)
    case .standard:
      drawList.fillRect(rect, color: HoverStyle.standardTint(in: context.theme, pressed: pressed))
    }
  }

}
