import Foundation
import Testing

@testable import Chroma

@MainActor
struct AppTests {
  @Test func runUsesTheExistingAppInstance() {
    let app = StatefulApp()
    let renderer = AppRenderer()

    app.run(on: renderer)

    #expect(renderer.title == "App \(app.identifier) — Test")
    let content = renderer.content as? TupleBlock
    #expect((content?.children.first as? AppContent)?.identifier == app.identifier)
  }
}

private struct StatefulApp: App {
  let identifier = UUID()

  var title: String { "App \(identifier)" }

  @MainActor var body: some Block {
    AppContent(identifier: identifier)
  }
}

private struct AppContent: PrimitiveBlock {
  let identifier: UUID

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    proposal
  }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {}
}

@MainActor
private final class AppRenderer: Renderer {
  let name = "Test"
  var content: (any Block)?
  var onClose: (() -> Void)?
  let interaction = Interaction()
  var title: String?

  func run(title: String) {
    self.title = title
  }
}
