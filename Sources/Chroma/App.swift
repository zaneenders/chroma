public protocol App {
  associatedtype Body: Block

  @MainActor @BlockBuilder var body: Body { get }

  init()

  var title: String { get }

  var windowSize: Size { get }

  var keyBindings: KeyBindings { get }
}

extension App {
  public var title: String { String(describing: Self.self) }
  public var windowSize: Size { Size(width: 800, height: 600) }
  public var keyBindings: KeyBindings { .defaults }

  @MainActor
  package func run(on renderer: any Renderer) {
    renderer.setKeyBindings(keyBindings)
    renderer.content = body
    renderer.run(title: "\(title) — \(renderer.name)")
  }
}
