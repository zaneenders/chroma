#if WAYLAND_BACKEND

import ImmediateGUI

public final class WaylandRenderer {
  /// Produces the draw list for one frame. Same contract as the Metal backend.
  public var buildFrame: (inout DrawList, Size) -> Void = { _, _ in }

  public init() {
    fatalError("WaylandBackend is not implemented yet.")
  }
}

#endif
