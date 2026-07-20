/// The entry point of an application, SwiftUI-style.
///
/// Conform on a type marked with `@main` (usually through a backend-provided
/// refinement such as `MetalApp`, which supplies `main()`), and declare the
/// root block in ``body``:
///
/// ```swift
/// @main
/// struct ChromaDemo: MetalApp {
///   var body: some Block { Specimen() }
/// }
/// ```
public protocol App {
  associatedtype Body: Block

  /// The root block of the application.
  @BlockBuilder var body: Body { get }

  init()

  /// The window title. Defaults to the type name.
  var title: String { get }

  /// The initial window size in points. Defaults to 800x600.
  var windowSize: Size { get }
}

extension App {
  public var title: String { String(describing: Self.self) }
  public var windowSize: Size { Size(width: 800, height: 600) }

  /// Hands ``body`` to `renderer` and starts the platform event loop.
  ///
  /// The body is captured once at launch; re-evaluation of stateful blocks
  /// arrives with the interaction layer.
  @MainActor
  public static func run(on renderer: any Renderer) {
    let app = Self()
    renderer.content = app.body
    renderer.run(title: "\(app.title) — \(renderer.name)")
  }
}
