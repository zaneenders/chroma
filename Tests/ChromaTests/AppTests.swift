import Foundation
import Testing

@testable import Chroma

@MainActor
struct AppTests {
  @Test func runUsesTheExistingAppInstance() throws {
    let app = StatefulApp()
    let renderer = AppRenderer()

    try app.run(on: renderer)

    #expect(renderer.title == "App \(app.identifier) — Test")
    #expect(renderer.runtime.scheduler.minimumRefreshRate == 24)
    #expect(renderer.runtime.scheduler.maximumRefreshRate == 48)
    #expect(
      renderer.frame.paintSnapshot.contains {
        if case .text(_, let text, _, _) = $0 { return text == app.identifier.uuidString }
        return false
      })
  }

  @Test func runPropagatesBackendErrors() {
    let expected = BackendError.notImplemented(backend: "Test")
    let renderer = FailingAppRenderer(error: expected)

    #expect(throws: expected) {
      try StatefulApp().run(on: renderer)
    }
  }
}

private struct StatefulApp: App {
  let identifier = UUID()

  var minimumRefreshRate: Double { 24 }
  var maximumRefreshRate: Double { 48 }
  var title: String { "App \(identifier)" }

  @MainActor func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    buffer.text(Text(identifier.uuidString), context: context)
  }
}

@MainActor
private final class FailingAppRenderer: Chroma.Host {
  let name = "Test"
  var frameObserver: FrameObserver?
  var onClose: (() -> Void)?
  let runtime = WindowRuntime()
  let error: BackendError

  init(error: BackendError) {
    self.error = error
  }

  func run(title: String) throws {
    throw error
  }
}

@MainActor
private final class AppRenderer: Chroma.Host {
  let name = "Test"
  var frameObserver: FrameObserver?
  var onClose: (() -> Void)?
  let runtime = WindowRuntime()
  var title: String?
  var frame = DrawList()

  func run(title: String) {
    self.title = title
    frame = runtime.render(viewport: Size(width: 400, height: 40), input: InputState(), onChange: {})
  }
}
