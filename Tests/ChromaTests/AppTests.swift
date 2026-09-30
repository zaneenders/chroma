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
    let root = renderer.content as? DeferredBlock<TupleBlock>
    #expect((root?.body.children.first as? AppContent)?.identifier == app.identifier)
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

  @MainActor var body: some Block {
    AppContent(identifier: identifier)
  }
}

private struct AppContent: PrimitiveBlock {
  let identifier: UUID

  var focusRule: FocusRule { .standard }

  func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    proposal
  }

  func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {}
}

@MainActor
private final class FailingAppRenderer: Chroma.Host {
  let name = "Test"
  var content: (any Block)?
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
  var content: (any Block)?
  var frameObserver: FrameObserver?
  var onClose: (() -> Void)?
  let runtime = WindowRuntime()
  var title: String?

  func run(title: String) {
    self.title = title
  }
}
