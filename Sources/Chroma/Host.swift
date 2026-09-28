@MainActor
package protocol Host: AnyObject {
  var name: String { get }

  var content: (any Block)? { get set }

  var frameObserver: FrameObserver? { get set }

  var onClose: (() -> Void)? { get set }

  var interaction: Interaction { get }

  func setKeyBindings(_ bindings: KeyBindings)

  func setMinimumRefreshRate(_ refreshRate: Double)

  func run(title: String) throws
}

extension Host {
  package func setKeyBindings(_ bindings: KeyBindings) {}
  package func setMinimumRefreshRate(_ refreshRate: Double) {}
}
