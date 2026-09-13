#if !os(macOS)
import Chroma
import DemoContent

#if os(Linux)
import WaylandBackend
#endif

#if os(Linux)
private protocol DemoApp: WaylandApp {}
#else
private protocol DemoApp: App {}

extension DemoApp {
  @MainActor
  static func main() throws {
    throw BackendError.unavailable(
      backend: "ChromaDemo",
      reason: "no graphical backend is enabled"
    )
  }
}
#endif

@main
struct ChromaDemo {
  @MainActor static func main() throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.contains("--help") || arguments.contains("-h") {
      print("usage: ChromaDemo [--capture-directory EXISTING_WRITABLE_DIRECTORY]")
      print("Default capture directory: the demo package directory (Example/). Save with Ctrl+Shift+G.")
      return
    }
    let capture = try DemoCaptureConfiguration.parse(arguments: &arguments)
    guard arguments.isEmpty else {
      throw DemoCaptureConfiguration.ConfigurationError.missingOrDuplicateDirectory
    }
    #if os(macOS)
    let modifier: KeyModifiers = .command
    #else
    let modifier: KeyModifiers = .superKey
    #endif
    ConfiguredDemo.configuration = try DemoApplication(
      shortcutModifier: modifier,
      captureConfiguration: capture ?? DemoCaptureConfiguration.nativeDefault())
    try ConfiguredDemo.main()
  }
}

private struct ConfiguredDemo: DemoApp {
  @MainActor static var configuration: DemoApplication?
  private let demo: DemoApplication
  init() { demo = Self.configuration ?? DemoApplication() }
  var title: String { demo.title }
  var windowSize: Size { demo.windowSize }
  var minimumRefreshRate: Double { demo.minimumRefreshRate }
  var frameObserver: FrameObserver? { demo.frameObserver }
  var keyBindings: KeyBindings { demo.keyBindings }
  var body: some Block { demo.body }
}

#endif
