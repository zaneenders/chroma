public enum HoverStyle: Equatable, Sendable {
  case standard
  case none
  case tint(Color)

  public static func standardTint(in theme: ChromaTheme, pressed: Bool = false) -> Color {
    let base = pressed ? theme.focus.pressedHighlight : theme.focus.highlight
    return Color(r: base.r, g: base.g, b: base.b, a: base.a * 0.5)
  }
}

extension Block {
  public func hover(_ style: HoverStyle) -> some Block {
    ContextModifier(content: self, operation: .hover(style))
  }
}
