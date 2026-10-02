import Chroma
import ChromaHeadless
import Observation

@main
struct Demo: HeadlessApp {
  @Observable @MainActor final class Model {
    var first = ""
    var second = ""
    var count = 0
  }
  private let model = Model()

  var keyBindings: KeyBindings {
    .desktopNavigation.overlay(
      KeyBindings {
        bind(.backspace, in: .editing, to: .editing(.backspace))
        bind(.delete, in: .editing, to: .editing(.deleteForward))
      })
  }

  var body: some Block {
    VStack(spacing: 12) {
      TextEditor("First", singleLine: true, text: { model.first }, onChange: { model.first = $0 })
      TextEditor("Second", singleLine: true, text: { model.second }, onChange: { model.second = $0 })
      Button("Count: \(model.count)") { model.count += 1 }
    }.padding(16)
  }
}
