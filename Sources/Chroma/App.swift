public protocol App {
  associatedtype Body: Block

  @MainActor @BlockBuilder var body: Body { get }

  init()

  var title: String { get }

  var windowSize: Size { get }

  /// The baseline number of frames rendered each second, even when there is no input.
  /// Input and explicit redraw requests may render additional frames. Set to `0` to
  /// render only when a redraw is requested.
  var minimumRefreshRate: Double { get }

  var keyBindings: KeyBindings { get }
}

extension App {
  public var title: String { String(describing: Self.self) }
  public var windowSize: Size { Size(width: 800, height: 600) }
  public var minimumRefreshRate: Double { 0 }
  public var keyBindings: KeyBindings { KeyBindings() }

  @MainActor
  package func run(on renderer: any Renderer) throws {
    renderer.setMinimumRefreshRate(minimumRefreshRate)
    renderer.setKeyBindings(keyBindings)
    renderer.content = body
    try renderer.run(title: "\(title) — \(renderer.name)")
  }
}
