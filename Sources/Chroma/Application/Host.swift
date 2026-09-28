@MainActor
package protocol Host: AnyObject {
  var name: String { get }

  var content: (any Block)? { get set }

  var frameObserver: FrameObserver? { get set }

  var onClose: (() -> Void)? { get set }

  var runtime: WindowRuntime { get }

  func setMinimumRefreshRate(_ refreshRate: Double)

  func run(title: String) throws
}

extension Host {
  package var interaction: Interaction { runtime.interaction }
}
