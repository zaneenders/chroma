import Chroma
import Observation
@testable import DemoContent

@Observable @MainActor
final class DemoState {
  enum Screen { case play, chat, image }
  private(set) var screen = Screen.play
  var showsHelp = false
  let play: PlayState
  let chat: ChatState

  init(automaticallyUpdates: Bool = true) {
    play = PlayState(automaticallyTicks: automaticallyUpdates)
    chat = ChatState(automaticallyStreams: automaticallyUpdates)
  }

  func open(_ screen: Screen) {
    if screen != .play { play.pause() }
    self.screen = screen
  }
}

@MainActor
public struct DemoApplication: App {
  let state: DemoState
  private let shortcutModifier: KeyModifiers

  public init() {
    #if os(macOS)
    self.init(shortcutModifier: .command)
    #else
    self.init(shortcutModifier: .control)
    #endif
  }

  public init(shortcutModifier: KeyModifiers) {
    self.init(state: DemoState(), shortcutModifier: shortcutModifier)
  }

  init(state: DemoState, shortcutModifier: KeyModifiers) {
    self.state = state
    self.shortcutModifier = shortcutModifier
  }

  public var title: String { "Chroma — Play / Chat" }
  public var windowSize: Size { Size(width: 1120, height: 840) }

  public var keyBindings: KeyBindings {
    demoKeyBindings(shortcutModifier: shortcutModifier).overlay {
      bind("1", modifiers: shortcutModifier, to: .application("demo.play"))
      bind("2", modifiers: shortcutModifier, to: .application("demo.chat"))
    }
  }

  public var body: some Block {
    VStack(spacing: 16) {
      Group("Navigation") {
        HStack(spacing: 10) {
          Text("CHROMA").fontScale(0.85).foregroundColor(DemoStyle.accent).navigationIgnored()
          Text("/ a little playground").fontScale(0.55).foregroundColor(DemoStyle.muted).navigationIgnored()
          Spacer()
          Button(
            "Play", fontScale: 0.6,
            style: state.screen == .play ? DemoStyle.selectedButton : DemoStyle.button
          ) { state.open(.play) }
          Button(
            "Chat", fontScale: 0.6,
            style: state.screen == .chat ? DemoStyle.selectedButton : DemoStyle.button
          ) { state.open(.chat) }
          Button(
            "Image", fontScale: 0.6,
            style: state.screen == .image ? DemoStyle.selectedButton : DemoStyle.button
          ) { state.open(.image) }
          Button(state.showsHelp ? "Hide keys" : "Keys", fontScale: 0.6) { state.showsHelp.toggle() }
        }
      }
      if state.screen == .play {
        PlayDemo(state: state.play).sizing(x: .grow, y: .grow)
      } else if state.screen == .image {
        ImageDemo().sizing(x: .grow, y: .grow)
      } else {
        ChatDemo(state: state.chat, shortcutModifier: shortcutModifier).sizing(x: .grow, y: .grow)
      }
      if state.showsHelp {
        Text(
          "d/f/j/k: move   l: enter / use   s: leave group / board\nEnter: activate   Esc: leave input   \(shortcutModifier == .command ? "Cmd" : "Ctrl")+1 / 2: Play / Chat"
        )
        .fontScale(0.5).foregroundColor(DemoStyle.muted).navigationIgnored()
      }
    }
    .padding(24).background(DemoStyle.background).chromaTheme(DemoStyle.theme)
    .onCommand(.application("demo.play")) {
      state.open(.play)
      return .handled
    }
    .onCommand(.application("demo.chat")) {
      state.open(.chat)
      return .handled
    }
  }
}
