import Testing

@testable import Chroma

@Suite struct ThemeTests {
  @Test func accentUpdatesInteractiveSemanticStyles() {
    let accent = Color(r: 1, g: 0.25, b: 0.5, a: 1)
    let theme = ChromaTheme.dark.accentColor(accent)

    #expect(theme.accent == accent)
    #expect(theme.button.pressedBackground == accent)
    #expect(theme.textField.editingBorder == accent)
    #expect(theme.focus.ring == accent)
  }

  @Test @MainActor func scopedThemeReachesDescendants() {
    let theme = ChromaTheme.light
    let context = RenderContext()
    let themed = context.withTheme(theme)

    #expect(themed.theme == theme)
    #expect(context.theme == .dark)
  }
}
