import Chroma

@MainActor
public struct DemoApplication: App {
  private let capture: DemoSceneCapture?
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
    itemCount: Int = 2_000, shortcutModifier: KeyModifiers, captureConfiguration: DemoCaptureConfiguration? = nil
  ) {
    capture = captureConfiguration.map { DemoSceneCapture(configuration: $0) }
    state = PerformanceDemoState(itemCount: itemCount)
    self.shortcutModifier = shortcutModifier
  }

  public var title: String { "Chroma Demo" }
  public var windowSize: Size { Size(width: 1100, height: 720) }

  public var frameObserver: FrameObserver? {
    guard let capture else { return nil }
    return { [capture] frame in capture.observe(frame) }
  }

  public var keyBindings: KeyBindings {
    let bindings = KeyBindings {
      bind("c", modifiers: shortcutModifier, to: .editing(.copy))
      bind("x", modifiers: shortcutModifier, to: .editing(.cut))
      bind("v", modifiers: shortcutModifier, to: .editing(.paste))
      bind("a", modifiers: shortcutModifier, to: .editing(.selectAll))
      bind(.backspace, to: .editing(.backspace))
      bind(.delete, to: .editing(.deleteForward))
      bind(.leftArrow, to: .editing(.moveCaretLeft))
      bind(.rightArrow, to: .editing(.moveCaretRight))
      bind(.upArrow, to: .editing(.moveCaretUp))
      bind(.downArrow, to: .editing(.moveCaretDown))
      bind(.upArrow, modifiers: .shift, to: .editing(.selectCaretUp))
      bind(.downArrow, modifiers: .shift, to: .editing(.selectCaretDown))
      bind(.home, to: .editing(.moveCaretToStart))
      bind(.end, to: .editing(.moveCaretToEnd))
      bind(.enter, to: .editing(.submit))
      bind(.escape, to: .editing(.endEditing))
    }
    guard capture != nil else { return bindings }
    return bindings.overlay {
      bind("g", modifiers: [.control, .shift], to: .application("demo.capture"))
    }
  }

  public var body: some Block {
    if let capture {
      VStack(spacing: 0) {
        PerformanceDemo(state: state).sizing(x: .grow, y: .grow)
        CaptureStatus(capture: capture)
      }
      .chromaTheme(.dark)
      .onCommand(.application("demo.capture")) {
        capture.request()
        return .handled
      }
    } else {
      PerformanceDemo(state: state).chromaTheme(.dark)
    }
  }
}

private struct CaptureStatus: Block {
  let capture: DemoSceneCapture
  @MainActor var body: some Block {
    Text(capture.status).fontScale(0.45).padding(4)
  }
}
