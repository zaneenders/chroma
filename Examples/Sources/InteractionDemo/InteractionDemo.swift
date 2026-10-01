import Chroma
import Foundation
import InteractionFixtures

#if os(macOS)
import MetalBackend
#elseif os(Linux)
import WaylandBackend
#endif

#if os(macOS)
private protocol DemoApp: MacOSApp {}
#elseif os(Linux)
private protocol DemoApp: WaylandApp {}
#else
private protocol DemoApp: App {}

extension DemoApp {
  @MainActor
  static func main() throws {
    throw BackendError.unavailable(
      backend: "InteractionDemo",
      reason: "no graphical backend is enabled"
    )
  }
}
#endif

@main
private struct InteractionDemo: DemoApp {
  private let count = Int(ProcessInfo.processInfo.environment["ROWS"] ?? "1000") ?? 1000
  private let lazy = ProcessInfo.processInfo.environment["LAZY"] == "1"
  private let counters = InteractionWorkloadCounters()
  var title: String { "Interaction — \(lazy ? "lazy" : "eager") / \(count) rows" }
  var windowSize: Size { Size(width: 400, height: 600) }
  var body: some Block { InteractionWorkload(count: count, lazy: lazy, counters: counters) }
}
