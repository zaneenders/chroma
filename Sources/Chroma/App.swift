public protocol App {
  associatedtype Body: Block

  @MainActor @BlockBuilder var body: Body { get }

  init()

  var title: String { get }

  var windowSize: Size { get }
}

extension App {
  public var title: String { String(describing: Self.self) }
  public var windowSize: Size { Size(width: 800, height: 600) }

  @MainActor
  package static func run(on renderer: any Renderer) {
    let app = Self()
    renderer.content = app.body
    renderer.run(title: "\(app.title) — \(renderer.name)")
  }
}
