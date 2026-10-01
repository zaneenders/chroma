@MainActor
public protocol App {
  associatedtype Body: Block

  @MainActor @BlockBuilder var body: Body { get }

  init()

  var title: String { get }

  var windowSize: Size { get }

  var minimumRefreshRate: Double { get }

  var maximumRefreshRate: Double { get }

  var keyBindings: KeyBindings { get }

  var frameObserver: FrameObserver? { get }
}

extension App {
  public var title: String { String(describing: Self.self) }
  public var windowSize: Size { Size(width: 800, height: 600) }
  public var minimumRefreshRate: Double { 30 }
  public var maximumRefreshRate: Double { 60 }
  public var keyBindings: KeyBindings { .modalNavigation }
  public var frameObserver: FrameObserver? { nil }

  @MainActor
  package func run(on host: any Host) throws {
    host.runtime.scheduler.setRefreshRates(minimum: minimumRefreshRate, maximum: maximumRefreshRate)
    host.runtime.keyBindings = keyBindings
    host.frameObserver = frameObserver
    host.content = DeferredBlock { self.body }
    try host.run(title: "\(title) — \(host.name)")
  }
}
