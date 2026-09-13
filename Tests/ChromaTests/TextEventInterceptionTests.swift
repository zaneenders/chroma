import Testing
@testable import Chroma

@MainActor
struct TextEventInterceptionTests {
  @Test func replacementPreservesOrderingAndFallback() {
    let interaction = Interaction()
    let context = RenderContext(interaction: interaction)
    let id = WidgetID("history")
    let rect = Rect(x: 0, y: 0, width: 100, height: 40)
    var text = ""
    func frame(_ events: [TextEditEvent]) -> TextInputState {
      interaction.beginFrame(input: InputState(textEvents: events))
      let state = context.textInputState(id: id, in: rect, text: text, onChange: { text = $0 },
        onEndEditing: { .handled }, onTextEvent: { event, buffer in
          event == .moveCaretUp && buffer.isEmpty ? "history" : nil
        })
      interaction.endFrame()
      return state
    }
    _ = frame([])
    context.focus(id, editing: true)
    let recalled = frame([.moveCaretUp])
    #expect(text == "history")
    #expect(recalled.caretOffset == 7)
    _ = frame([.moveCaretLeft, .insert("!")])
    #expect(text == "histor!y")
    #expect(frame([.endEditing]).editing)
    text = ""
    _ = frame([.insert("draft"), .moveCaretUp])
    #expect(text == "draft")
    context.endEditing()
    #expect(context.activeTextInput == nil)
  }
}
