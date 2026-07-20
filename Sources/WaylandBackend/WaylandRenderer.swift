#if WAYLAND_BACKEND

import Chroma

/// The Wayland backend (stub).
///
/// Conforms to ``Renderer`` so application code is already backend-neutral;
/// the implementation lands with the Wayland event loop and surface setup.
@MainActor
public final class WaylandRenderer: Renderer {
  public let name = "Wayland"

  /// The content rendered every frame. Same contract as the Metal backend.
  public var content: (any Block)?

  /// The interaction context. Input pumping lands with the event loop.
  public let interaction = Interaction()

  public init() {}

  public func run(title: String = "Hello Triangle") {
    fatalError("WaylandBackend is not implemented yet.")
  }
}

#endif
