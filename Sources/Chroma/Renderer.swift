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
/// ``run(title:)``, pump platform input into ``interaction`` once per frame
/// before drawing, and expose ``content`` so blocks can be swapped at any
/// time.
@MainActor
public protocol Renderer: AnyObject {
  /// A short human-readable backend name, e.g. "Metal" or "Wayland".
  var name: String { get }

  /// The content rendered every frame. Assign a new block at any time to swap
  /// content without touching the backend.
  var content: (any Block)? { get set }

  /// Called once when the standalone window or event loop closes.
  var onClose: (() -> Void)? { get set }

  /// The interaction context this backend feeds with platform input. Install
  /// it as ``Interaction/current`` so blocks can reach it, and call
  /// ``Interaction/beginFrame(input:)`` at the start of every frame.
  var interaction: Interaction { get }

  /// Creates the platform window, installs the rendering surface, and runs
  /// the platform event loop. Returns when the application exits.
  func run(title: String)
}
