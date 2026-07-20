#if WAYLAND_BACKEND

import ImmediateGUI

/// An ``App`` that runs on the Wayland backend.
///
/// Apply `@main` to a conforming type; `main()` comes from this extension.
public protocol WaylandApp: App {}

extension WaylandApp {
  @MainActor
  public static func main() {
    Self.run(on: WaylandRenderer())
  }
}

#endif
