@MainActor
package protocol Renderer: AnyObject {
  var name: String { get }

  var content: (any Block)? { get set }

  var onClose: (() -> Void)? { get set }

  var interaction: Interaction { get }

  func setKeyBindings(_ bindings: KeyBindings)

  func setMinimumRefreshRate(_ refreshRate: Double)

  func run(title: String)
}

extension Renderer {
  package func setKeyBindings(_ bindings: KeyBindings) {}
  package func setMinimumRefreshRate(_ refreshRate: Double) {}
}
