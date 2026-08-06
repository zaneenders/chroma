#if METAL_BACKEND

import Chroma

public protocol MetalApp: App {}

extension MetalApp {
  @MainActor
  public static func main() {
    let app = Self()
    guard let renderer = MetalRenderer(size: app.windowSize) else {
      fatalError("Metal requires Apple Silicon or supported GPU.")
    }
    app.run(on: renderer)
  }
}

#endif
