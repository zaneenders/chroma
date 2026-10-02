import ChromaTesting
import Observation
import Testing

@testable import Chroma

@Suite(ControlledObservationDelivery())
@MainActor
struct CapturedTextInputTests {
  @Observable final class Model {
    var text = "abcdef"
  }

  final class Capture {
    var range: Range<Int>?
  }

  struct Editor: LifecycleElement {
    let text: String
    let model: Model
    let capture: Capture

    var focusRule: FocusRule { .control }

    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }

    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {}
    func prepareInteraction(in rect: Rect, context: BlockContext) {
      let state = context.textInputState(
        id: WidgetID("editor"), in: rect, text: { text }, onChange: { model.text = $0 })
      capture.range = state.selectionRange
    }
  }

  @Test func capturedTextSelectionIsClampedToCurrentText() {
    let model = Model()
    let capture = Capture()
    let renderer = HeadlessHost()
    renderer.content = DeferredBlock { Editor(text: model.text, model: model, capture: capture) }
    renderer.render()
    renderer.render(input: InputState(commands: [.navigation(.down), .action(.activate)]))
    renderer.render(input: InputState(textEvents: [.selectAll]))
    model.text = "a"
    renderer.render()
    #expect(capture.range == 0..<1)
    renderer.close()
  }

  @Test func editsUseCurrentCapturedText() {
    let model = Model()
    let capture = Capture()
    let renderer = HeadlessHost()
    renderer.content = DeferredBlock { Editor(text: model.text, model: model, capture: capture) }
    renderer.render()
    renderer.render(input: InputState(commands: [.navigation(.down), .action(.activate)]))
    model.text = "a"
    renderer.render(input: InputState(textEvents: [.insert("!")]))
    #expect(model.text == "a!")
    renderer.close()
  }

  @Test func builtInTextEditorHandlesShrinkingCapturedText() {
    let model = Model()
    let renderer = HeadlessHost()
    func field(_ text: String) -> TextEditor {
      TextEditor(singleLine: true, text: { text }, onChange: { model.text = $0 })
    }
    renderer.content = DeferredBlock { field(model.text) }
    renderer.render()
    renderer.render(input: InputState(commands: [.navigation(.down), .action(.activate)]))
    renderer.render(input: InputState(textEvents: [.selectAll]))
    model.text = "a"
    renderer.render()
    model.text = ""
    renderer.render()
    renderer.close()
  }
}
