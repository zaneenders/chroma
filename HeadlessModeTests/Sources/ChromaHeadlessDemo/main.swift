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

  func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    let first = buffer.textEditor(
      TextEditor("First", singleLine: true, text: { model.first }, onChange: { model.first = $0 }),
      context: context.childScope(0))
    let second = buffer.textEditor(
      TextEditor("Second", singleLine: true, text: { model.second }, onChange: { model.second = $0 }),
      context: context.childScope(1))
    let count = buffer.button(
      Button("Count: \(model.count)") { model.count += 1 }, context: context.childScope(2))
    let stack = buffer.stack([first, second, count], axis: .vertical, spacing: 12, context: context)
    return buffer.padding(stack, 16, context: context)
  }
}
