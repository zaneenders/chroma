import Chroma

@MainActor
public struct DemoApplication: App {
  private let workspace = WorkspaceState()
  private let state: PerformanceDemoState
  private let shortcutModifier: KeyModifiers

  public init() {
    #if os(macOS)
    self.init(shortcutModifier: .command)
    #else
    self.init(shortcutModifier: .control)
    #endif
  }

  public init(
    itemCount: Int = 2_000, shortcutModifier: KeyModifiers
  ) {
    state = PerformanceDemoState(itemCount: itemCount)
    self.shortcutModifier = shortcutModifier
  }

  public var title: String { "Chroma — Move through the interface" }
  public var windowSize: Size { Size(width: 1200, height: 820) }

  public var keyBindings: KeyBindings {
    var bindings = KeyBindings.modalNavigation.overlay {
      bind("c", modifiers: shortcutModifier, to: .editing(.copy))
      bind("x", modifiers: shortcutModifier, to: .editing(.cut))
      bind("v", modifiers: shortcutModifier, to: .editing(.paste))
      bind("a", modifiers: shortcutModifier, to: .editing(.selectAll))
      bind(.backspace, to: .editing(.backspace))
      bind(.delete, to: .editing(.deleteForward))
      bind(.home, to: .editing(.moveCaretToStart))
      bind(.end, to: .editing(.moveCaretToEnd))
      bind(.enter, to: .editing(.submit))
      bind(.escape, to: .editing(.endEditing))
    }
    #if os(Linux)
    if shortcutModifier == .control || shortcutModifier == .superKey {
      let alternate: KeyModifiers = shortcutModifier == .control ? .superKey : .control
      bindings = bindings.overlay {
        bind("c", modifiers: alternate, to: .editing(.copy))
        bind("x", modifiers: alternate, to: .editing(.cut))
        bind("v", modifiers: alternate, to: .editing(.paste))
        bind("a", modifiers: alternate, to: .editing(.selectAll))
      }
    }
    #endif
    return bindings
  }

  public var body: some Block {
    WorkspaceDemo(state: workspace, gallery: state)
      .sizing(x: .grow, y: .grow)
      .chromaTheme(.dark)
  }
}
