import Testing

@testable import Chroma

@MainActor
struct NavigationContractTests {
  @MainActor private final class Harness {
    let runtime = WindowRuntime()
    var context: LayoutContext { runtime.context }
    private var currentContent: LayoutBuilder = { buffer, context in
      return buffer.empty(context: context)
    }

    init() {
      runtime.build = { [unowned self] buffer, context in
        currentContent(&buffer, context)
      }
    }
    @discardableResult func render(
      _ content: @escaping LayoutBuilder, _ commands: [Command] = [], text: [TextEditEvent] = []
    )
      -> DrawList
    {
      currentContent = content
      return runtime.render(
        viewport: Size(width: 600, height: 400),
        input: InputState(commands: commands, textEvents: text), onChange: {})
    }
  }

  @Test func tabTraversesLeavesAcrossGroupsAndLeavesEditing() {
    let h = Harness()
    let first = FocusTarget()
    let field = FocusTarget()
    let last = FocusTarget()
    let content: LayoutBuilder = { buffer, context in
      let node254 = buffer.group("First", context: context.childScope(0)) { buffer, context in
        let node253 = buffer.focus(
          first, context: context.childScope(0),
          content: { buffer, context in
            return buffer.button(Button("One") {}, context: context)
          })
        return node253
      }
      let node260 = buffer.group("Second", context: context.childScope(1)) { buffer, context in
        let node256 = buffer.focus(
          field, context: context.childScope(0),
          content: { buffer, context in
            let node255 = buffer.textEditor(
              TextEditor(singleLine: true, text: { "" }, onChange: { _ in }), context: context)
            return node255
          })
        let node258 = buffer.focus(
          last, context: context.childScope(1),
          content: { buffer, context in
            return buffer.button(Button("Three") {}, context: context)
          })
        return buffer.overlay([node256, node258], group: false, context: context)
      }
      return buffer.stack([node254, node260], axis: .vertical, context: context)
    }
    h.render(content)
    h.render(content, [.navigation(.nextFocus)])
    #expect(first.isFocused)
    h.render(content, [.navigation(.nextFocus)])
    #expect(field.isFocused)
    field.focus(editing: true)
    h.render(content)
    #expect(field.isEditing)
    h.render(content, [.navigation(.nextFocus)])
    #expect(last.isFocused)
    #expect(!field.isEditing)
    h.render(content, [.navigation(.nextFocus)])
    #expect(first.isFocused)
    h.render(content, [.navigation(.previousFocus)])
    #expect(last.isFocused)
  }

  @Test func plainMovementStopsAtBoundaryAndShiftSkipsLocalPeers() {
    let h = Harness()
    let input = FocusTarget()
    let send = FocusTarget()
    let content: LayoutBuilder = { buffer, context in
      let node263 = buffer.group("Sessions", context: context.childScope(0)) { buffer, context in
        return buffer.button(Button("Session") {}, context: context.childScope(0))
      }
      let node264 = buffer.sizing(node263, x: .fixed(150), y: .grow, context: context.childScope(0))
      let node270 = buffer.group("Composer", context: context.childScope(1)) { buffer, context in
        let node266 = buffer.focus(
          input, context: context.childScope(0).childScope(0),
          content: { buffer, context in
            let node265 = buffer.textEditor(
              TextEditor(singleLine: true, text: { "" }, onChange: { _ in }), context: context)
            return node265
          })
        let node268 = buffer.focus(
          send, context: context.childScope(0).childScope(1),
          content: { buffer, context in
            return buffer.button(Button("Send") {}, context: context)
          })
        return buffer.stack([node266, node268], axis: .horizontal, context: context.childScope(0))
      }
      let node271 = buffer.sizing(node270, x: .grow, y: .grow, context: context.childScope(1))
      return buffer.stack([node264, node271], axis: .horizontal, spacing: 20, context: context)
    }
    h.render(content)
    input.focus()
    h.render(content)
    h.render(content, [.navigation(.left)])
    #expect(input.isFocused)
    h.render(content, [.navigation(.right)])
    #expect(send.isFocused)
    h.render(content, [.navigation(.sectionLeft)])
    #expect(h.context.navigationBreadcrumb == ["Window", "Sessions"])
    #expect(h.context.interaction.selectedLeafID == nil)
  }

  @Test func layoutOnlyContentUsesTheSameUnselectedRoot() {
    let h = Harness()
    var calls = 0
    let content: LayoutBuilder = { buffer, context in
      let node273 = buffer.button(Button("One") { calls += 1 }, context: context.childScope(0))
      let node274 = buffer.button(Button("Two") {}, context: context.childScope(1))
      return buffer.stack([node273, node274], axis: .horizontal, context: context)
    }
    h.render(content)
    #expect(h.context.interaction.selection == nil)
    h.render(content, [.navigation(.stepIn)])
    #expect(calls == 0)
    h.render(content, [.navigation(.right), .navigation(.stepIn)])
    #expect(calls == 1)
  }

  @Test func hoverAppearanceDoesNotRemoveNavigation() {
    let h = Harness()
    let content: LayoutBuilder = { buffer, context in
      var context276 = context.childScope(0)
      context276.hoverStyle = HoverStyle.none
      let node277 = buffer.text(Text("Hidden tint"), context: context276)
      var context278 = context.childScope(1)
      context278.navigationIgnored = true
      let node279 = buffer.text(Text("Decoration"), context: context278)
      let node280 = buffer.button(Button("Action") {}, context: context.childScope(2))
      return buffer.stack([node277, node279, node280], axis: .vertical, context: context)
    }
    h.render(content)
    #expect(h.context.interaction.navigation?.children.count == 2)
    h.render(content, [.navigation(.down)])
    #expect(h.context.interaction.selectedLeafID != nil)
    #expect(h.context.interaction.navigationPath == [0])
  }

  @Test func wideContentMovesToFirstAlignedAction() {
    let h = Harness()
    let save = FocusTarget()
    let content: LayoutBuilder = { buffer, context in
      let node289 = buffer.group(context: context) { buffer, context in
        let node282 = buffer.text(
          Text("A wide message spanning the entire action row"), context: context.childScope(0).childScope(0))
        let node283 = buffer.sizing(node282, x: .grow, context: context.childScope(0).childScope(0))
        let node285 = buffer.focus(
          save, context: context.childScope(0).childScope(1).childScope(0),
          content: { buffer, context in
            return buffer.button(Button("Save") {}, context: context)
          })
        let node286 = buffer.button(Button("Quote") {}, context: context.childScope(0).childScope(1).childScope(1))
        let node287 = buffer.stack([node285, node286], axis: .horizontal, context: context.childScope(0).childScope(1))
        return buffer.stack([node283, node287], axis: .vertical, context: context.childScope(0))
      }
      return node289
    }
    h.render(content)
    h.render(content, [.navigation(.down), .navigation(.stepIn), .navigation(.down)])
    #expect(save.isFocused)
  }

  @Test func shiftSelectsTextAndControlMovesSectionsWithoutPreventingUppercaseTyping() {
    for (key, command, selection): (Character, NavigationCommand, TextEditEvent) in [
      ("d", .sectionLeft, .selectCaretLeft), ("f", .sectionUp, .selectCaretUp),
      ("j", .sectionDown, .selectCaretDown), ("k", .sectionRight, .selectCaretRight),
    ] {
      let shifted = KeyboardInput(chord: KeyChord(key, modifiers: .shift), text: String(key).uppercased())
      let controlled = KeyboardInput(chord: KeyChord(key, modifiers: .control))
      #expect(KeyBindings.vimNavigation.resolve(shifted, isTextEditing: false) == .text(selection))
      #expect(
        KeyBindings.vimNavigation.resolve(shifted, isTextEditing: true) == .text(.insert(String(key).uppercased())))
      #expect(KeyBindings.vimNavigation.resolve(controlled, isTextEditing: false) == .command(.navigation(command)))
      #expect(KeyBindings.vimNavigation.resolve(controlled, isTextEditing: true) == .command(.navigation(command)))
    }
  }

  @Test func keyboardCopiesMultilineUnicodeAndPastesIntoEditor() throws {
    let h = Harness()
    var draft = ""
    let content: LayoutBuilder = { buffer, context in
      let node290 = buffer.text(Text("café\n👨‍👩‍👧‍👦 tea").selectable(), context: context.childScope(0))
      let node291 = buffer.textEditor(
        TextEditor(singleLine: true, text: { draft }, onChange: { draft = $0 }), context: context.childScope(1))
      return buffer.stack([node290, node291], axis: .vertical, context: context)
    }
    h.render(content)
    h.render(content, [.navigation(.down), .navigation(.stepIn)])
    #expect(h.context.isSelectingText)
    #expect(h.context.interaction.caretOffset == 0)
    let frame = h.render(content, text: [.selectCaretRight, .selectCaretDown, .selectCaretRight])
    let copied = try #require(h.context.interaction.copyText())
    #expect(copied == "café\n👨‍👩‍👧‍👦 ")
    let highlights = frame.paintSnapshot.filter {
      if case .fillRect(let rect, let color) = $0 {
        return color == h.context.theme.focus.selectionBackground
          && rect.size.height == h.context.fontMetrics.lineAdvance
      }
      return false
    }
    #expect(highlights.count == 2)
    h.render(content, text: [.insert("not allowed"), .deleteForward])
    #expect(h.context.interaction.copyText() == copied)
    #expect(!h.context.interaction.acceptsTextInsertion)
    h.render(content, text: [.endEditing])
    h.render(content, [.navigation(.stepOut), .navigation(.down), .action(.activate)])
    #expect(h.context.interaction.acceptsTextInsertion)
    h.render(content, text: [.insert(copied)])
    #expect(draft == copied)
  }

  @Test func horizontalSelectionReversesAndShrinkingContentClampsIt() {
    let h = Harness()
    @MainActor final class Value { var text = "abcd" }
    let value = Value()
    let content: LayoutBuilder = { buffer, context in
      return buffer.text(Text(value.text).selectable(), context: context)
    }
    h.render(content)
    h.render(content, [.navigation(.down), .navigation(.stepIn)])
    h.render(content, text: [.selectCaretRight, .selectCaretRight, .selectCaretLeft])
    #expect(h.context.interaction.copyText() == "a")
    value.text = ""
    h.render(content)
    #expect(h.context.interaction.textSelectionRange == nil)
    #expect(h.context.interaction.caretOffset == 0)
  }
}

extension NavigationContractTests {
  @Test func textIsAnotherMovementLevelAndInputPreservesSelection() {
    let h = Harness()
    var value = "abcd"
    let field = FocusTarget()
    let content: LayoutBuilder = { buffer, context in
      let node298 = buffer.group("Composer", context: context) { buffer, context in
        let node295 = buffer.focus(
          field, context: context.childScope(0).childScope(0),
          content: { buffer, context in
            let node294 = buffer.textEditor(
              TextEditor(singleLine: true, text: { value }, onChange: { value = $0 }), context: context)
            return node294
          })
        let node296 = buffer.button(Button("Send") {}, context: context.childScope(0).childScope(1))
        return buffer.stack([node295, node296], axis: .horizontal, context: context.childScope(0))
      }
      return node298
    }
    func press(_ key: Character, shift: Bool = false) {
      let input = KeyboardInput(
        chord: KeyChord(key, modifiers: shift ? .shift : []),
        text: shift ? String(key).uppercased() : String(key))
      guard let resolved = h.context.interaction.resolve(input, appBindings: .vimNavigation) else {
        Issue.record("Key was not resolved")
        return
      }
      switch resolved {
      case .command(let command): h.render(content, [command])
      case .text(let event): h.render(content, text: [event])
      }
    }
    h.render(content)
    field.focus()
    h.render(content)
    press("l")
    #expect(h.context.interaction.mode == .movement)
    #expect(h.context.isSelectingText)
    #expect(!field.isEditing)
    #expect(h.context.interaction.caretOffset == 4)
    press("d")
    press("d", shift: true)
    #expect(h.context.interaction.copyText() == "c")
    h.render(content, [.action(.activate)])
    #expect(field.isEditing)
    #expect(h.context.interaction.textSelectionRange == 2..<3)
    press("k", shift: true)
    #expect(value == "abKd")
    h.render(content, text: [.endEditing])
    #expect(h.context.interaction.mode == .movement)
    #expect(h.context.isSelectingText)
    #expect(h.context.interaction.caretOffset == 3)
    press("d")
    #expect(h.context.interaction.caretOffset == 2)
    press("s")
    #expect(!h.context.isSelectingText)
    #expect(field.isFocused)
    press("s")
    #expect(h.context.navigationBreadcrumb == ["Window", "Composer"])
  }

  @Test func readOnlyTextCannotEnterInputAndMovesAcrossLines() {
    let h = Harness()
    let content: LayoutBuilder = { buffer, context in
      return buffer.text(Text("ab\ncd").selectable(), context: context)
    }
    h.render(content)
    h.render(content, [.navigation(.down), .navigation(.stepIn)])
    h.render(content, [.navigation(.right)])
    h.render(content, text: [.selectCaretDown])
    #expect(h.context.interaction.copyText() == "b\nc")
    h.render(content, [.navigation(.sectionDown)])
    #expect(h.context.interaction.copyText() == nil)
    h.render(content, [.action(.activate)])
    #expect(h.context.interaction.mode == .movement)
    #expect(!h.context.interaction.acceptsTextInsertion)
    h.render(content, [.navigation(.stepOut)])
    #expect(h.context.interaction.editingLeaf == nil)
    #expect(h.context.interaction.selectedLeafID != nil)
  }

  @Test func arrowKeysHaveNoDefaultBindingsInEitherMode() {
    for key: Key in [.leftArrow, .rightArrow, .upArrow, .downArrow] {
      for modifiers: KeyModifiers in [[], .shift] {
        for editing in [false, true] {
          #expect(
            KeyBindings.vimNavigation.resolve(
              KeyboardInput(chord: KeyChord(key, modifiers: modifiers)), isTextEditing: editing) == nil)
        }
      }
    }
  }
}
