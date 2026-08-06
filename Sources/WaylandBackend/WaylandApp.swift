#if WAYLAND_BACKEND

import Chroma

public protocol WaylandApp: App {}

extension WaylandApp {
  @MainActor
  public static func main() {
    let app = Self()
    app.run(on: WaylandRenderer())
  }
}

#endif
