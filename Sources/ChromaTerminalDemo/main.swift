import Chroma
import TerminalBackend

@main
struct ChromaTerminalDemo: TerminalApp {
  final class State { var message = "Use JKFDSL to navigate and activate a button" }
  private let state = State()

  var title: String { "Chroma Terminal Demo" }
  var minimumRefreshRate: Double { 2 }

  var keyBindings: KeyBindings {
    KeyBindings {
      bind("j", to: .navigation(.down))
      bind("f", to: .navigation(.up))
      bind("d", to: .navigation(.left))
      bind("k", to: .navigation(.right))
      bind("l", to: .navigation(.in))
      bind("s", to: .navigation(.out))
    }
  }

  var body: some Block {
    ThemeReader { theme in
      VStack(spacing: 1) {
        Text("Chroma Terminal Backend").foregroundColor(theme.accent)
        Text(state.message).foregroundColor(theme.secondaryForeground)
        HStack(spacing: 2) {
          Button("Hello", id: WidgetID("hello")) { state.message = "Hello from Chroma" }
          Button("Terminal", id: WidgetID("terminal")) { state.message = "Rendered in terminal cells" }
        }
        Text("J down · F up · D left · K right · L in · S out")
          .foregroundColor(theme.secondaryForeground)
        Text("Ctrl-C or Ctrl-D exits")
      }
      .padding(2)
      .background(theme.background)
    }
    .chromaTheme(.dark)
  }
}
