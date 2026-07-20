/// A rendering backend: owns the platform window and event loop, and renders
/// a ``Block`` every frame.
///
/// Application code builds one block and hands it to any conformer, so
/// swapping backends never touches UI code:
///
/// ```swift
/// let renderer = MetalRenderer(size: Size(width: 800, height: 600))
/// renderer.content = MyBlock()
/// renderer.run(title: "My App")
/// ```
///
/// To add a new backend, conform a type to this protocol: consume `DrawList`
/// commands in your frame callback, create your platform window in
/// ``run(title:)``, and expose ``content`` so blocks can be swapped at any
/// time.
@MainActor
public protocol Renderer: AnyObject {
  /// A short human-readable backend name, e.g. "Metal" or "Wayland".
  var name: String { get }

  /// The content rendered every frame. Assign a new block at any time to swap
  /// content without touching the backend.
  var content: (any Block)? { get set }

  /// Creates the platform window, installs the rendering surface, and runs
  /// the platform event loop. Returns when the application exits.
  func run(title: String)
}
