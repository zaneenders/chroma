#if METAL_BACKEND

import Chroma

public protocol MetalApp: App {}

extension MetalApp {
  @MainActor
  public static func main() throws {
    let app = Self()
    let renderer = try MetalRenderer(size: app.windowSize)
    try app.run(on: renderer)
  }
}

#endif
