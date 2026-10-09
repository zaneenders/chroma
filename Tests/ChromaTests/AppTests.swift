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

  @MainActor var body: some Block {
    AppContent(identifier: identifier)
  }
}

private struct AppContent: Block {

  @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    let context = context.component(Self.self)
    return buffer.customLeaf(
      context: context, focusRule: focusRule,
      expandsHorizontally: false, expandsVertically: false,
      measure: { sizeThatFits($0, context: context) },
      register: { register(in: $0, context: context) },
      paint: { paint(into: &$0, in: $1, context: context) })
  }

  @MainActor func register(in rect: Rect, context: BlockContext) {}

  let identifier: UUID

  var focusRule: FocusRule { .standard }

  @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    proposal
  }

  @MainActor func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    drawList.text(identifier.uuidString, at: rect.origin, color: .white)
  }
}

@MainActor
private final class FailingAppRenderer: Chroma.Host {
  let name = "Test"
  var build: LayoutBuilder?
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
  var build: LayoutBuilder?
  var frameObserver: FrameObserver?
  var onClose: (() -> Void)?
  let runtime = WindowRuntime()
  var title: String?
  var frame = DrawList()

  func run(title: String) {
    self.title = title
    guard let build else { return }
    var buffer = LayoutBuffer()
    let node = build(&buffer, BlockContext())
    let rect = Rect(x: 0, y: 0, width: 400, height: 40)
    buffer.register(node, in: rect)
    buffer.paint(node, into: &frame, in: rect)
  }
}
