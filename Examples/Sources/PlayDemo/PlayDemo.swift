import Chroma
import DemoContent

#if os(macOS)
import MetalBackend
#elseif os(Linux)
import WaylandBackend
#endif

#if os(macOS)
private protocol DemoApp: MacOSApp {}
#elseif os(Linux)
private protocol DemoApp: WaylandApp {}
#else
private protocol DemoApp: App {}

extension DemoApp {
  @MainActor
  static func main() throws {
    throw BackendError.unavailable(
      backend: "PlayDemo",
      reason: "no graphical backend is enabled"
    )
  }
}
#endif

@main
private struct PlayDemo: DemoApp {
  private let demo = PlayApplication()
  var title: String { demo.title }
  var windowSize: Size { demo.windowSize }
  var keyBindings: KeyBindings { demo.keyBindings }
  var body: some Block { demo.body }
}
