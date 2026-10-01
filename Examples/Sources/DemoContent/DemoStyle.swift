import Chroma

enum DemoStyle {
  static let background = Color(r: 0.045, g: 0.05, b: 0.065, a: 1)
  static let panel = Color(r: 0.075, g: 0.082, b: 0.1, a: 1)
  static let card = Color(r: 0.11, g: 0.12, b: 0.14, a: 1)
  static let border = Color(r: 0.18, g: 0.2, b: 0.23, a: 1)
  static let accent = Color(r: 0.65, g: 0.87, b: 0.72, a: 1)
  static let muted = Color(r: 0.57, g: 0.61, b: 0.66, a: 1)

  static let button = ButtonStyle(
    idleBackground: card, pressedBackground: border, foreground: .white, border: border,
    cornerRadius: 8)
  static let selectedButton = ButtonStyle(
    idleBackground: accent, pressedBackground: .white, foreground: background, border: accent,
    cornerRadius: 8)

  static var theme: ChromaTheme {
    var theme = ChromaTheme.dark.accentColor(accent)
    theme.background = background
    theme.surface = panel
    theme.elevatedSurface = card
    theme.border = border
    theme.secondaryForeground = muted
    theme.button = button
    theme.textEditor = TextEditorStyle(
      idleBackground: background, editingBackground: background, foreground: .white,
      placeholder: muted, caret: accent, border: border, editingBorder: accent, cornerRadius: 8)
    theme.focus.highlight = Color(r: accent.r, g: accent.g, b: accent.b, a: 0.12)
    theme.focus.selectionBackground = Color(r: accent.r, g: accent.g, b: accent.b, a: 0.3)
    return theme
  }
}
