import ChromaTesting
import Testing

@testable import Chroma

@MainActor
struct TextEditorSelectionCommandTests {
  @Test func clickingFieldThenEscapingAllowsShiftSelectionInMovementMode() {
    var text = "Copy this text"
    let test = NavigationTestHost(
      build: { buffer, context in
        buffer.textEditor(TextEditor(singleLine: true, text: { text }, onChange: { text = $0 }), context: context)
      },
      keyBindings: .modalNavigation)
    let point = Point(x: 45, y: 15)
    test.host.render(
      input: InputState(pointerPosition: point, pointerPressPosition: point, pointerDown: true, pointerPressed: true))
    test.host.render(input: InputState(pointerPosition: point, pointerPressPosition: point, pointerReleased: true))
    let interaction = test.host.runtime.interaction
    #expect(interaction.isTextEditing)
    #expect(interaction.editingLeaf != nil)
    test.press(KeyboardInput(chord: KeyChord(.escape)))
    #expect(!interaction.isTextEditing)
    #expect(interaction.editingLeaf != nil)
    test.press(KeyboardInput(chord: KeyChord("d", modifiers: .shift), text: "D"))
    #expect(interaction.textSelectionRange != nil)
    #expect(interaction.copyText() != nil)
  }

  @Test func singleLineEditorDoesNotWrapAndEnterDoesNotInsertNewline() {
    var text = "abcdefghijklmnopqrstuvwxyz"
    let focus = FocusTarget()
    let test = NavigationTestHost(
      build: { buffer, context in
        buffer.focus(focus, context: context) { buffer, context in
          buffer.textEditor(TextEditor(singleLine: true, text: { text }, onChange: { text = $0 }), context: context)
        }
      },
      size: Size(width: 100, height: 44))
    focus.focus(editing: true)
    let frame = test.host.render(input: InputState(textEvents: [.moveCaretToEnd]))
    #expect(
      frame.paintSnapshot.contains {
        if case .text(_, let value, _, _) = $0 { return value == text }
        return false
      })
    #expect(
      !frame.paintSnapshot.contains {
        if case .text(_, let value, _, _) = $0 { return value == "abcdefg" }
        return false
      })
    test.host.render(input: InputState(textEvents: [.submit]))
    #expect(text == "abcdefghijklmnopqrstuvwxyz")
  }

  @Test func shiftArrowsExtendReverseAndCollapseEditorSelection() {
    var text = "abcd"
    let focus = FocusTarget()
    let test = NavigationTestHost(
      build: { buffer, context in
        buffer.focus(focus, context: context) { buffer, context in
          buffer.textEditor(TextEditor(text: { text }, onChange: { text = $0 }), context: context)
        }
      },
      keyBindings: .desktopNavigation)
    focus.focus(editing: true)
    test.host.render(input: InputState(textEvents: [.moveCaretToEnd]))
    let interaction = test.host.runtime.interaction
    #expect(interaction.caretOffset == 4)

    test.press(KeyboardInput(chord: KeyChord(.leftArrow, modifiers: .shift)))
    #expect(interaction.textSelectionRange == 3..<4)
    #expect(interaction.copyText() == "d")
    test.press(KeyboardInput(chord: KeyChord(.leftArrow, modifiers: .shift)))
    #expect(interaction.textSelectionRange == 2..<4)
    test.press(KeyboardInput(chord: KeyChord(.rightArrow, modifiers: .shift)))
    #expect(interaction.textSelectionRange == 3..<4)
    test.press(KeyboardInput(chord: KeyChord(.rightArrow, modifiers: .shift)))
    #expect(interaction.textSelectionRange == nil)
    #expect(interaction.caretOffset == 4)
    test.press(KeyboardInput(chord: KeyChord(.leftArrow, modifiers: .shift)))
    test.press(KeyboardInput(chord: KeyChord(.leftArrow)))
    #expect(interaction.textSelectionRange == nil)
    #expect(interaction.caretOffset == 3)
    #expect(text == "abcd")
  }

  @Test func editorSelectAllAndReplacementPreserveGraphemeOffsets() {
    var text = "a👨‍👩‍👧‍👦\ncd"
    let focus = FocusTarget()
    let test = NavigationTestHost(
      build: { buffer, context in
        buffer.focus(focus, context: context) { buffer, context in
          buffer.textEditor(TextEditor(text: { text }, onChange: { text = $0 }), context: context)
        }
      },
      keyBindings: KeyBindings.desktopNavigation.overlay {
        bind("a", modifiers: .command, to: .editing(.selectAll))
      })
    focus.focus(editing: true)
    test.host.render(input: InputState(textEvents: [.moveCaretToEnd]))
    let interaction = test.host.runtime.interaction

    test.press(KeyboardInput(chord: KeyChord("a", modifiers: .command)))
    #expect(interaction.textSelectionRange == 0..<text.count)
    #expect(interaction.copyText() == text)
    test.host.render(input: InputState(textEvents: [.insert("X")]))
    #expect(text == "X")
    #expect(interaction.caretOffset == 1)
    #expect(interaction.textSelectionRange == nil)
    test.host.render(input: InputState(textEvents: [.selectAll, .deleteForward]))
    #expect(text == "")
    #expect(interaction.textSelectionRange == nil)
    #expect(interaction.caretOffset == 0)
  }

  @Test func editorVerticalSelectionUsesVisualRowsAndCanReverse() {
    var text = "ab\ncd\nef"
    let focus = FocusTarget()
    let test = NavigationTestHost(
      build: { buffer, context in
        buffer.focus(focus, context: context) { buffer, context in
          buffer.textEditor(TextEditor(text: { text }, onChange: { text = $0 }), context: context)
        }
      },
      keyBindings: .desktopNavigation)
    focus.focus(editing: true)
    test.host.render(input: InputState(textEvents: [.moveCaretToEnd]))
    let interaction = test.host.runtime.interaction
    #expect(interaction.caretOffset == text.count)

    test.press(KeyboardInput(chord: KeyChord(.upArrow, modifiers: .shift)))
    #expect(interaction.textSelectionRange == 5..<8)
    #expect(interaction.copyText() == "\nef")
    test.press(KeyboardInput(chord: KeyChord(.upArrow, modifiers: .shift)))
    #expect(interaction.textSelectionRange == 2..<8)
    test.press(KeyboardInput(chord: KeyChord(.downArrow, modifiers: .shift)))
    #expect(interaction.textSelectionRange == 5..<8)
    test.press(KeyboardInput(chord: KeyChord(.downArrow, modifiers: .shift)))
    #expect(interaction.textSelectionRange == nil)
    #expect(interaction.caretOffset == text.count)
  }
}
