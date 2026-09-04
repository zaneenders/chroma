#if WAYLAND_BACKEND

import Chroma

public protocol WaylandApp: App {}

extension WaylandApp {
  @MainActor
  public static func main() throws {
    let app = Self()
    try app.run(on: WaylandRenderer(size: app.windowSize))

  }
}

#endif
