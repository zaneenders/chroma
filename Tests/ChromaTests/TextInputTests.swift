import Testing
@testable import Chroma

/// Tests for text input: insert mode as the editing half of the one-cursor
/// model.
///
/// Tests drive `Interaction` the way the backend and blocks do:
/// `beginFrame` (carrying input), a simulated draw registering the field and
/// a sibling leaf, then `endFrame`. The fixture tree:
///
/// ```
/// root (vertical)      0,0   100x40
/// ├─ name (text leaf)  0,0   100x20
/// └─ b (leaf)          0,20  100x20
/// ```
@MainActor
struct TextInputTests {

  /// Runs one frame against the fixture tree, applying any edits to `text`
  /// the way the field's `onChange` would, and returns the field's state.
  /// Pass `includeField: false` to simulate the field vanishing mid-edit.
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

  /// Builds the tree and activates the field with the keyboard.
  private func enterInsertMode(_ ctx: Interaction, text: inout String) {
    frame(ctx, text: &text)  // cursor starts on the first leaf: the field
    frame(ctx, input: InputState(commands: [.activate]), text: &text)
  }

  // MARK: Entering insert mode

  /// An `activate` command on the selected field starts an editing session
  /// with the caret at the end of the text.
  @Test func activateEntersInsertMode() {
    let ctx = Interaction()
    var text = "abc"
    frame(ctx, text: &text)
    let state = frame(ctx, input: InputState(commands: [.activate]), text: &text)
    #expect(state.editing)
    #expect(state.caretOffset == 3)
    #expect(ctx.isTextEditing)
  }

  /// A full click — press then release on the field — enters insert mode,
  /// through the same activation path as the keyboard.
  @Test func clickEntersInsertMode() {
    let ctx = Interaction()
    var text = "hi"
    frame(ctx, text: &text)
    frame(ctx, input: InputState(commands: [.down]), text: &text)  // cursor on b
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

  // MARK: Editing

  /// Inserted text lands at the caret and the caret tracks it; edits are
  /// reported through `onChange`.
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

  /// Backspace deletes the grapheme before the caret and stops at the start
  /// of the text.
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

  /// Caret movement clamps at both ends of the text.
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

  /// Text events with no active session edit nothing.
  @Test func eventsWithoutSessionDoNothing() {
    let ctx = Interaction()
    var text = "abc"
    let state = frame(ctx, input: InputState(textEvents: [.insert("X")]), text: &text)
    #expect(text == "abc")
    #expect(!state.editing)
  }

  // MARK: Leaving insert mode

  /// The `.endEditing` event (escape, or return on a single-line field)
  /// ends the session without touching the text.
  @Test func endEditingExitsInsertMode() {
    let ctx = Interaction()
    var text = "abc"
    enterInsertMode(ctx, text: &text)
    let state = frame(ctx, input: InputState(textEvents: [.endEditing]), text: &text)
    #expect(!state.editing)
    #expect(state.caretOffset == nil)
    #expect(!ctx.isTextEditing)
    #expect(text == "abc")
  }

  /// There is only one cursor: a navigation command that moves it off the
  /// field ends the editing session.
  @Test func cursorLeavingEndsInsertMode() {
    let ctx = Interaction()
    var text = "abc"
    enterInsertMode(ctx, text: &text)
    let state = frame(ctx, input: InputState(commands: [.down]), text: &text)
    #expect(ctx.selection == [0, 1], "the cursor moved to the sibling leaf")
    #expect(!state.editing)
    #expect(!ctx.isTextEditing)
  }

  /// If the field vanishes from the tree mid-edit, the session ends rather
  /// than holding a dangling ID.
  @Test func vanishingFieldEndsSession() {
    let ctx = Interaction()
    var text = "abc"
    enterInsertMode(ctx, text: &text)
    #expect(ctx.isTextEditing)
    frame(ctx, text: &text, includeField: false)
    #expect(!ctx.isTextEditing)
  }
}
