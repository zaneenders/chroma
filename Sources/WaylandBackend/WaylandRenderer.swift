#if WAYLAND_BACKEND

import Chroma

@MainActor
public final class WaylandRenderer: Renderer {
  public let name = "Wayland"

  public var content: (any Block)?
  public var onClose: (() -> Void)?

  public let interaction = Interaction()

  public init() {}

  public func run(title: String = "Hello Triangle") {
    fatalError("WaylandBackend is not implemented yet.")
  }
}

#endif
