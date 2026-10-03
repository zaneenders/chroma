import Testing

@testable import Chroma

@MainActor
struct CustomTextSelectionTests {
  private final class Renderer {
    var text = "café\n👨‍👩‍👧‍👦 tea"
    var state: TextInputState?
  }

  private struct ReadOnlyText: PaintableBlock {

    let renderer: Renderer
    var focusRule: FocusRule { .standard }

    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
      Size(width: 200, height: 40)
    }

    func register(in rect: Rect, context: BlockContext) {
      let layout = TextLayout(renderer.text)
      renderer.state = context.textSelectionState(
        in: rect, text: { renderer.text },
        pointerOffset: { point, _ in
          layout.offset(
            row: Int((point.y - rect.minY) / 20),
            column: Int((point.x - rect.minX) / 10))
        },
        verticalOffset: { layout.verticalOffset($0, direction: $1) })
    }
    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      renderer.state = context.textInputVisualState()
    }
  }

  @Test func customRendererSelectsCopiesAndRejectsMutations() {
    let context = BlockContext()
    let producer = FrameProducer()
    let renderer = Renderer()
    let target = FocusTarget()
    let content = Group("Response") { ReadOnlyText(renderer: renderer).focusTarget(target) }
    func render(_ commands: [Command] = [], text: [TextEditEvent] = []) {
      _ = producer.render(
        content: content, viewport: Size(width: 600, height: 400),
        input: InputState(commands: commands, textEvents: text), context: context, onChange: {})
    }
    render()
    target.focus()
    render()
    render([.navigation(.stepIn)])
    #expect(context.isSelectingText)
    #expect(renderer.state?.caretOffset == 0)
    render(text: [.selectCaretRight, .selectCaretDown, .selectCaretRight])
    #expect(renderer.state?.selectionRange == 0..<7)
    #expect(context.interaction.copyText() == "café\n👨‍👩‍👧‍👦 ")
    render([.action(.activate)])
    #expect(!context.interaction.acceptsTextInsertion)
    #expect(renderer.state?.editing == false)
    render(text: [.insert("changed"), .backspace, .deleteForward, .cut, .paste, .submit])
    #expect(renderer.text == "café\n👨‍👩‍👧‍👦 tea")
    #expect(renderer.state?.selectionRange == 0..<7)
    render(text: [.selectAll])
    #expect(context.interaction.copyText() == renderer.text)
    renderer.text = "a"
    render()
    #expect(renderer.state?.selectionRange == 0..<1)
    #expect(renderer.state?.caretOffset == 1)
    render([.action(.cancel)])
    #expect(!context.isSelectingText)
    #expect(renderer.state?.caretOffset == nil)
    #expect(target.isFocused)
    render([.navigation(.stepIn)])
    render([.navigation(.stepOut)])
    #expect(!context.isSelectingText)
    #expect(target.isFocused)
  }

  @Test func mouseAndKeyboardUseTheSameCustomSelection() {
    let context = BlockContext()
    let producer = FrameProducer()
    let renderer = Renderer()
    let content = ReadOnlyText(renderer: renderer)
    func render(_ input: InputState = InputState()) {
      _ = producer.render(
        content: content, viewport: Size(width: 600, height: 400),
        input: input, context: context, onChange: {})
    }
    render()
    render(InputState(pointerPosition: Point(x: 10, y: 5), pointerDown: true, pointerPressed: true))
    render(InputState(pointerPosition: Point(x: 30, y: 5), pointerDown: true))
    render(InputState(pointerPosition: Point(x: 30, y: 5), pointerReleased: true))
    #expect(renderer.state?.selectionRange == 1..<3)
    #expect(context.interaction.copyText() == "af")
    render(InputState(textEvents: [.selectCaretRight]))
    #expect(renderer.state?.selectionRange == 1..<4)
    #expect(context.interaction.copyText() == "afé")
  }
}
