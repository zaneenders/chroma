#if WAYLAND_BACKEND

import Chroma

public protocol WaylandApp: App {}

extension WaylandApp {
  @MainActor
  public static func main() {
    Self.run(on: WaylandRenderer())
  }
}

#endif
