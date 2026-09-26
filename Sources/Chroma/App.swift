@MainActor
public protocol App {
  associatedtype Body: Block

  @MainActor @BlockBuilder var body: Body { get }

  init()

  var title: String { get }

  var windowSize: Size { get }

  var minimumRefreshRate: Double { get }

  var keyBindings: KeyBindings { get }

  var frameObserver: FrameObserver? { get }
}

extension App {
  public var title: String { String(describing: Self.self) }
  public var windowSize: Size { Size(width: 800, height: 600) }
  public var minimumRefreshRate: Double { 0 }
  public var keyBindings: KeyBindings { .vimNavigation }
  public var frameObserver: FrameObserver? { nil }

  @MainActor
  package func run(on renderer: any Renderer) throws {
    renderer.setMinimumRefreshRate(minimumRefreshRate)
    renderer.setKeyBindings(keyBindings)
    renderer.frameObserver = frameObserver
    renderer.content = DeferredBlock { self.body }
    try renderer.run(title: "\(title) — \(renderer.name)")
  }
}
