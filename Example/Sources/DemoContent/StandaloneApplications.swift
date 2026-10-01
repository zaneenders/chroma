import Chroma
import Observation

@Observable @MainActor
final class DemoHelpState {
  var isVisible = false
}

@MainActor
struct DemoShell<Content: Block>: Block {
  let title: String
  let help: DemoHelpState
  let content: Content

  var body: some Block {
    VStack(spacing: 16) {
      HStack(spacing: 10) {
        Text("CHROMA / \(title)").fontScale(0.85)
          .foregroundColor(DemoStyle.accent).navigationIgnored()
        Spacer()
        Button(help.isVisible ? "Hide keys" : "Keys", fontScale: 0.6) {
          help.isVisible.toggle()
        }
      }
      content.sizing(x: .grow, y: .grow)
      if help.isVisible {
        Text("d/f/j/k: move   l: enter / use   s: leave group / board\nEnter: activate   Esc: leave input")
          .fontScale(0.5).foregroundColor(DemoStyle.muted).navigationIgnored()
      }
    }
    .padding(24).background(DemoStyle.background).chromaTheme(DemoStyle.theme)
  }
}

@MainActor
public struct PlayApplication: App {
  let state: PlayState
  private let help = DemoHelpState()

  public init() { state = PlayState() }
  init(state: PlayState) { self.state = state }

  public var title: String { "Chroma — Play" }
  public var windowSize: Size { Size(width: 1120, height: 840) }
  public var keyBindings: KeyBindings { demoKeyBindings(shortcutModifier: demoShortcutModifier) }
  public var body: some Block {
    DemoShell(title: "Play", help: help, content: PlayDemo(state: state))
  }
}

@MainActor
public struct ChatApplication: App {
  let state: ChatState
  private let help = DemoHelpState()
  private let shortcutModifier: KeyModifiers

  public init() {
    self.init(state: ChatState(), shortcutModifier: demoShortcutModifier)
  }
  init(state: ChatState, shortcutModifier: KeyModifiers) {
    self.state = state
    self.shortcutModifier = shortcutModifier
  }

  public var title: String { "Chroma — Chat" }
  public var windowSize: Size { Size(width: 1120, height: 840) }
  public var keyBindings: KeyBindings { demoKeyBindings(shortcutModifier: shortcutModifier) }
  public var body: some Block {
    DemoShell(
      title: "Chat", help: help,
      content: ChatDemo(state: state, shortcutModifier: shortcutModifier))
  }
}

@MainActor
public struct ImageApplication: App {
  private let help = DemoHelpState()

  public init() {}

  public var title: String { "Chroma — Image" }
  public var windowSize: Size { Size(width: 1120, height: 840) }
  public var keyBindings: KeyBindings { demoKeyBindings(shortcutModifier: demoShortcutModifier) }
  public var body: some Block {
    DemoShell(title: "Image", help: help, content: ImageDemo())
  }
}
