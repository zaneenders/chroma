import Testing

@testable import Chroma

@MainActor
struct NavigationContractTests {
  @MainActor private final class Harness {
    let context = RenderContext()
    let producer = FrameProducer()
    @discardableResult func render(_ content: any Block, _ commands: [Command] = [], text: [TextEditEvent] = [])
      -> DrawList
    {
      producer.render(
        content: content, viewport: Size(width: 600, height: 400),
        input: InputState(commands: commands, textEvents: text), context: context, onChange: {})
    }
  }

  @Test func plainMovementStopsAtBoundaryAndShiftSkipsLocalPeers() {
    let h = Harness()
    let input = FocusTarget()
    let send = FocusTarget()
    let content = HStack(spacing: 20) {
      Group("Sessions") { Button("Session") {} }.sizing(x: .fixed(150), y: .grow)
      Group("Composer") {
        HStack {
          TextField(text: { "" }, onChange: { _ in }).focusTarget(input)
          Button("Send") {}.focusTarget(send)
        }
      }.sizing(x: .grow, y: .grow)
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
    let content = HStack {
      Button("One") { calls += 1 }
      Button("Two") {}
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
    let content = VStack {
      Text("Hidden tint").hover(.none)
      Text("Decoration").navigationIgnored()
      Button("Action") {}
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
    let content = Group {
      VStack {
        Text("A wide message spanning the entire action row").sizing(x: .grow)
        HStack {
          Button("Save") {}.focusTarget(save)
          Button("Quote") {}
        }
      }
    }
    h.render(content)
    h.render(content, [.navigation(.down), .navigation(.stepIn), .navigation(.down)])
    #expect(save.isFocused)
  }

  @Test func shiftedMovementBindingsPreserveUppercaseTyping() {
    for (key, command): (Character, NavigationCommand) in [
      ("d", .sectionLeft), ("f", .sectionUp), ("j", .sectionDown), ("k", .sectionRight),
    ] {
      let input = KeyboardInput(chord: KeyChord(key, modifiers: .shift), text: String(key).uppercased())
      #expect(KeyBindings.vimNavigation.resolve(input, isTextEditing: false) == .command(.navigation(command)))
      #expect(KeyBindings.vimNavigation.resolve(input, isTextEditing: true) == .text(.insert(String(key).uppercased())))
    }
  }

  @Test func keyboardCopiesMultilineUnicodeAndPastesIntoEditor() throws {
    let h = Harness()
    var draft = ""
    let content = VStack {
      Text("café\n👨‍👩‍👧‍👦 tea").selectable()
      TextField(text: { draft }, onChange: { draft = $0 })
    }
    h.render(content)
    h.render(content, [.navigation(.down), .navigation(.stepIn)])
    #expect(h.context.isSelectingText)
    #expect(h.context.interaction.caretOffset == 0)
    let frame = h.render(content, text: [.selectCaretRight, .selectCaretDown, .selectCaretRight])
    let copied = try #require(h.context.interaction.copyText())
    #expect(copied == "café\n👨‍👩‍👧‍👦 ")
    let highlights = frame.commands.filter {
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
    h.render(content, [.navigation(.down), .navigation(.stepIn)])
    #expect(h.context.interaction.acceptsTextInsertion)
    h.render(content, text: [.insert(copied)])
    #expect(draft == copied)
  }

  @Test func horizontalSelectionReversesAndShrinkingContentClampsIt() {
    let h = Harness()
    @MainActor final class Value { var text = "abcd" }
    let value = Value()
    let content = DeferredBlock { Text(value.text).selectable() }
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
