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

  @MainActor struct Editor {

    func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
      let context = context.component(Self.self)
      return buffer.customLeaf(
        context: context, focusRule: focusRule,
        measure: { self.sizeThatFits($0, context: context) },
        register: { self.register(in: $0, context: context) },
        paint: { self.paint(into: &$0, in: $1, context: context) })
    }

    let text: String
    let model: Model
    let capture: Capture

    var focusRule: FocusRule { .control }

    @MainActor func sizeThatFits(_ proposal: Size, context: LayoutContext) -> Size { proposal }

    func register(in rect: Rect, context: LayoutContext) {
      let state = context.textInputState(
        id: WidgetID("editor"), in: rect, text: { text }, onChange: { model.text = $0 })
      capture.range = state.selectionRange
    }
    func paint(into list: inout DrawList, in rect: Rect, context: LayoutContext) {
      capture.range = context.textInputVisualState(id: WidgetID("editor")).selectionRange
    }
  }

  @Test func capturedTextSelectionIsClampedToCurrentText() {
    let model = Model()
    let capture = Capture()
    let renderer = HeadlessHost()
    renderer.build = { buffer, context in
      return Editor(text: model.text, model: model, capture: capture).build(into: &buffer, context: context)
    }
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
    renderer.build = { buffer, context in
      return Editor(text: model.text, model: model, capture: capture).build(into: &buffer, context: context)
    }
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
    renderer.build = { buffer, context in
      buffer.textEditor(field(model.text), context: context)
    }
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
