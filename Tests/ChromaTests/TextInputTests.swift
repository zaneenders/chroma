import Testing

@testable import Chroma

@MainActor
struct TextInputTests {

  @discardableResult
  private func frame(
    _ ctx: Interaction,
    input: InputState = InputState(),
    text: inout String,
    includeField: Bool = true
  ) -> TextInputState {
    ctx.beginFrame(input: input)
    var result = TextInputState(hovered: false, held: false, editing: false, caretOffset: nil)
    ctx.beginGroup(.vertical, rect: Rect(x: 0, y: 0, width: 100, height: 40))
    if includeField {
      result = ctx.textInputBehavior(
        id: WidgetID("name"), rect: Rect(x: 0, y: 0, width: 100, height: 20),
        text: text, onChange: { text = $0 })
    }
    _ = ctx.interactiveBehavior(
      id: WidgetID("b"), rect: Rect(x: 0, y: 20, width: 100, height: 20))
    ctx.endGroup()
    ctx.endFrame()
    return result
  }

  private func enterInsertMode(_ ctx: Interaction, text: inout String) {
    frame(ctx, text: &text)
    frame(ctx, input: InputState(commands: [.activate]), text: &text)
  }

  @Test func activateEntersInsertMode() {
    let ctx = Interaction()
    var text = "abc"
    frame(ctx, text: &text)
    let state = frame(ctx, input: InputState(commands: [.activate]), text: &text)
    #expect(state.editing)
    #expect(state.caretOffset == 3)
    #expect(ctx.isTextEditing)
    #expect(ctx.mode == .editing)
  }

  @Test func clickEntersInsertMode() {
    let ctx = Interaction()
    var text = "hi"
    frame(ctx, text: &text)
    frame(ctx, input: InputState(commands: [.down]), text: &text)
    frame(
      ctx,
      input: InputState(
        pointerPosition: Point(x: 10, y: 10), pointerDown: true, pointerPressed: true),
      text: &text)
    let state = frame(
      ctx,
      input: InputState(pointerPosition: Point(x: 10, y: 10), pointerReleased: true),
      text: &text)
    #expect(state.editing)
    #expect(state.caretOffset == 2)
    #expect(ctx.isTextEditing)
  }

  @Test func typingInsertsAtCaret() {
    let ctx = Interaction()
    var text = "abc"
    enterInsertMode(ctx, text: &text)
    var state = frame(ctx, input: InputState(textEvents: [.insert("X")]), text: &text)
    #expect(text == "abcX")
    #expect(state.caretOffset == 4)
    state = frame(
      ctx,
      input: InputState(textEvents: [.moveCaretLeft, .moveCaretLeft, .insert("Y")]),
      text: &text)
    #expect(text == "abYcX")
    #expect(state.caretOffset == 3)
  }

  @Test func backspaceDeletesBeforeCaret() {
    let ctx = Interaction()
    var text = "ab"
    enterInsertMode(ctx, text: &text)
    var state = frame(ctx, input: InputState(textEvents: [.backspace]), text: &text)
    #expect(text == "a")
    #expect(state.caretOffset == 1)
    state = frame(ctx, input: InputState(textEvents: [.backspace, .backspace]), text: &text)
    #expect(text == "", "the second backspace hits the start of the text and does nothing")
    #expect(state.caretOffset == 0)
  }

  @Test func caretMovementClamps() {
    let ctx = Interaction()
    var text = "ab"
    enterInsertMode(ctx, text: &text)
    var state = frame(ctx, input: InputState(textEvents: [.moveCaretRight]), text: &text)
    #expect(state.caretOffset == 2, "already at the end")
    state = frame(
      ctx, input: InputState(textEvents: [.moveCaretToStart, .moveCaretLeft]), text: &text)
    #expect(state.caretOffset == 0, "clamped at the start")
    state = frame(ctx, input: InputState(textEvents: [.moveCaretToEnd]), text: &text)
    #expect(state.caretOffset == 2)
  }

  @Test func eventsWithoutSessionDoNothing() {
    let ctx = Interaction()
    var text = "abc"
    let state = frame(ctx, input: InputState(textEvents: [.insert("X")]), text: &text)
    #expect(text == "abc")
    #expect(!state.editing)
  }

  @Test func unicodeEditingUsesGraphemeClusterOffsets() {
    let ctx = Interaction()
    var text = "A👨‍👩‍👧‍👦e\u{301}"
    enterInsertMode(ctx, text: &text)

    var state = frame(ctx, input: InputState(textEvents: [.moveCaretLeft]), text: &text)
    #expect(state.caretOffset == 2)
    state = frame(ctx, input: InputState(textEvents: [.backspace]), text: &text)
    #expect(text == "Ae\u{301}", "backspace removes the whole emoji grapheme")
    #expect(state.caretOffset == 1)

    state = frame(ctx, input: InputState(textEvents: [.deleteForward]), text: &text)
    #expect(text == "A", "forward delete removes the whole combining grapheme")
    #expect(state.caretOffset == 1)

    state = frame(ctx, input: InputState(textEvents: [.insert("🇺🇸")]), text: &text)
    #expect(text == "A🇺🇸")
    #expect(state.caretOffset == 2)
  }

  @Test func selectAllReplacesTheFieldContentsOnInsert() {
    let ctx = Interaction()
    var text = "hello"
    enterInsertMode(ctx, text: &text)

    var state = frame(ctx, input: InputState(textEvents: [.selectAll]), text: &text)
    #expect(ctx.textSelectionRange == 0..<5)
    #expect(ctx.copyText() == "hello")
    #expect(state.caretOffset == 5)

    state = frame(ctx, input: InputState(textEvents: [.insert("world")]), text: &text)
    #expect(text == "world")
    #expect(ctx.textSelectionRange == nil)
    #expect(state.caretOffset == 5)
  }

  @Test func selectAllThenDeleteClearsTheField() {
    let ctx = Interaction()
    var text = "hello"
    enterInsertMode(ctx, text: &text)

    let state = frame(
      ctx, input: InputState(textEvents: [.selectAll, .deleteForward]), text: &text)
    #expect(text.isEmpty)
    #expect(ctx.textSelectionRange == nil)
    #expect(state.caretOffset == 0)
  }

  @Test func selectAllThenBackspaceClearsTheField() {
    let ctx = Interaction()
    var text = "hello"
    enterInsertMode(ctx, text: &text)

    let state = frame(ctx, input: InputState(textEvents: [.selectAll, .backspace]), text: &text)
    #expect(text.isEmpty)
    #expect(ctx.textSelectionRange == nil)
    #expect(state.caretOffset == 0)
  }

  @Test func endEditingExitsInsertMode() {
    let ctx = Interaction()
    var text = "abc"
    enterInsertMode(ctx, text: &text)
    let state = frame(ctx, input: InputState(textEvents: [.endEditing]), text: &text)
    #expect(!state.editing)
    #expect(state.caretOffset == nil)
    #expect(!ctx.isTextEditing)
    #expect(ctx.mode == .movement)
    #expect(text == "abc")
  }

  @Test func handledEndEditingKeepsInsertModeActive() {
    let ctx = Interaction()
    var text = "abc"
    enterInsertMode(ctx, text: &text)

    ctx.beginFrame(input: InputState(textEvents: [.endEditing]))
    ctx.beginGroup(.vertical, rect: Rect(x: 0, y: 0, width: 100, height: 40))
    let state = ctx.textInputBehavior(
      id: WidgetID("name"), rect: Rect(x: 0, y: 0, width: 100, height: 20),
      text: text, onChange: { text = $0 }, onEndEditing: { .handled })
    ctx.endGroup()
    ctx.endFrame()

    #expect(state.editing)
    #expect(ctx.isTextEditing)
    #expect(ctx.mode == .editing)
    #expect(text == "abc")
  }

  @Test func cursorLeavingEndsInsertMode() {
    let ctx = Interaction()
    var text = "abc"
    enterInsertMode(ctx, text: &text)
    let state = frame(ctx, input: InputState(commands: [.down]), text: &text)
    #expect(ctx.selection == [0, 1], "the cursor moved to the sibling leaf")
    #expect(!state.editing)
    #expect(!ctx.isTextEditing)
    #expect(ctx.mode == .movement)
  }

  @Test func vanishingFieldEndsSession() {
    let ctx = Interaction()
    var text = "abc"
    enterInsertMode(ctx, text: &text)
    #expect(ctx.isTextEditing)
    frame(ctx, text: &text, includeField: false)
    #expect(!ctx.isTextEditing)
  }
}
