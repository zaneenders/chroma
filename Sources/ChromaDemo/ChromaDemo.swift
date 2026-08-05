import Chroma
import Foundation

#if METAL_BACKEND
import MetalBackend
typealias PlatformApp = MetalApp
#elseif WAYLAND_BACKEND
import WaylandBackend
typealias PlatformApp = WaylandApp
#else
#error(
  "ChromaDemo requires a rendering backend: MetalBackend (enabled by default) or WaylandBackend."
)
#endif

@main
struct ChromaDemo: PlatformApp {
  var title: String { "Chroma" }
  var windowSize: Size { Size(width: 1040, height: 720) }

  private let state = DemoState()

  var body: some Block {
    Entry(state: state)
      .chromaTheme(ChromaTheme.dark.accentColor(state.accent))
  }
}
