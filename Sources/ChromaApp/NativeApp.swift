import Chroma

#if os(macOS)
import MetalBackend
#elseif os(Linux)
import WaylandBackend
#endif

public protocol NativeApp: App {}

extension NativeApp {
  @MainActor
  public static func main() throws {
    #if os(macOS)
    let app = Self()
    try app.run(on: MacOSHost(size: app.windowSize))
    #elseif os(Linux)
    let app = Self()
    try app.run(on: WaylandHost(size: app.windowSize))
    #else
    throw BackendError.unavailable(backend: "ChromaApp", reason: "no graphical backend is enabled")
    #endif
  }
}
