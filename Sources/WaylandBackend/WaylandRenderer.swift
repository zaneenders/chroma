#if WAYLAND_BACKEND

import Chroma

@MainActor
public final class WaylandRenderer: Renderer {
  public let name = "Wayland"

  public var content: (any Block)?
  public var onClose: (() -> Void)?

  package let interaction = Interaction()

  public init() {}

  public func run(title: String = "Hello Triangle") throws {
    throw BackendError.notImplemented(backend: name)
  }
}

#endif
