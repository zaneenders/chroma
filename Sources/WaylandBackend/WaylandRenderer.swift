#if WAYLAND_BACKEND

import ImmediateGUI

/// The Wayland backend (stub).
///
/// Conforms to ``Renderer`` so application code is already backend-neutral;
/// the implementation lands with the Wayland event loop and surface setup.
@MainActor
public final class WaylandRenderer: Renderer {
  public let name = "Wayland"

  /// The content rendered every frame. Same contract as the Metal backend.
  public var content: (any Block)?

  public init() {}

  public func run(title: String = "Hello Triangle") {
    fatalError("WaylandBackend is not implemented yet.")
  }
}

#endif
