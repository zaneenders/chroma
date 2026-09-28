extension DrawList {
  mutating func textInputBackground(
    in rect: Rect, style: TextFieldStyle, editing: Bool, hover: Color? = nil
  ) {
    fillRoundedRect(rect, radius: style.cornerRadius, color: editing ? style.editingBackground : style.idleBackground)
    if !editing, let hover { fillRoundedRect(rect, radius: style.cornerRadius, color: hover) }
    strokeRoundedRect(
      rect, radius: style.cornerRadius, width: style.borderWidth,
      color: editing ? style.editingBorder : style.border)
  }

  mutating func textInputLine(
    _ line: String, at origin: Point, scale: Float, foreground: Color,
    selection: Rect?, theme: FocusStyle
  ) {
    text(line, at: origin, color: foreground, scale: scale)
    guard let selection else { return }
    fillRect(selection, color: theme.selectionBackground)
    pushClip(selection)
    text(line, at: origin, color: theme.selectionForeground, scale: scale)
    popClip()
  }
}
