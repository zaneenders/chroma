import Testing

@testable import Chroma

@MainActor
struct DocumentSelectionTests {
  @Test func selectionCrossesTextLeavesInDepthFirstOrderAndShrinks() {
    let context = LayoutContext()
    let producer = FrameProducer()
    let first = FocusTarget()
    let content: LayoutBuilder = { buffer, context in
      let node59 = buffer.group("Session", context: context) { buffer, context in
        let node54 = buffer.focus(
          first, context: context.childScope(0),
          content: { buffer, context in
            return buffer.text(Text("ab").selectable(), context: context)
          })
        let node56 = buffer.group("Nested", context: context.childScope(1)) { buffer, context in
          return buffer.text(Text("café").selectable(), context: context.childScope(0))
        }
        let node57 = buffer.text(Text("end").selectable(), context: context.childScope(2))
        return buffer.overlay([node54, node56, node57], group: false, context: context)
      }
      return node59
    }
    func render(_ events: [TextEditEvent] = [], commands: [Command] = []) {
      _ = producer.render(
        build: content, viewport: Size(width: 500, height: 500),
        input: InputState(commands: commands, textEvents: events), context: context, onChange: {})
    }
    render()
    first.focus()
    render()
    render(commands: [.navigation(.stepIn)])
    render([.selectCaretRight])
    render([.selectCaretRight])
    render([.selectCaretRight])
    render([.selectCaretRight])
    #expect(context.interaction.copyText() == "ab\nc")
    render([.selectCaretLeft])
    render([.selectCaretLeft])
    render([.selectCaretLeft])
    #expect(context.interaction.copyText() == "a")
  }

  @Test func selectAllUsesSelectedGroupAndRootAndExcludesEditors() {
    let context = LayoutContext()
    let producer = FrameProducer()
    let first = FocusTarget()
    let content: LayoutBuilder = { buffer, context in
      let node64 = buffer.group("Session", context: context.childScope(0)) { buffer, context in
        let node61 = buffer.focus(
          first, context: context.childScope(0),
          content: { buffer, context in
            return buffer.text(Text("one").selectable(), context: context)
          })
        let node62 = buffer.text(Text("two").selectable(), context: context.childScope(1))
        return buffer.overlay([node61, node62], group: false, context: context)
      }
      let node65 = buffer.text(Text("outside").selectable(), context: context.childScope(1))
      let node66 = buffer.textEditor(
        TextEditor(text: { "private draft" }, onChange: { _ in }), context: context.childScope(2))
      return buffer.stack([node64, node65, node66], axis: .vertical, context: context)
    }
    func render(_ commands: [Command] = []) {
      _ = producer.render(
        build: content, viewport: Size(width: 500, height: 500),
        input: InputState(commands: commands), context: context, onChange: {})
    }
    render()
    first.focus()
    render()
    render([.navigation(.stepOut)])
    context.interaction.selectAll(at: .zero)
    #expect(context.interaction.copyText() == "one\ntwo")
    context.interaction.navigationPath = []
    context.interaction.selectAll(at: .zero)
    #expect(context.interaction.copyText() == "one\ntwo\noutside")
  }
}

@MainActor
struct VirtualizedTextSelectionTests {
  @Test func selectableTextInsideRowsRegistersForDocumentSelectionAndFocus() {
    let context = LayoutContext()
    let producer = FrameProducer()
    let target = FocusTarget()
    let controller = ScrollViewController()
    let content: LayoutBuilder = { buffer, context in
      let node68 = buffer.scrollView(
        ScrollView(
          controller: controller,
          rows: [
            .init(
              id: "tool",
              build: { buffer, context in
                let first = buffer.focus(target, context: context.childScope(0)) { buffer, context in
                  buffer.text(Text("read_file").selectable(), context: context)
                }
                let second = buffer.text(Text("arguments\noutput").selectable(), context: context.childScope(1))
                return buffer.stack([first, second], axis: .vertical, context: context)
              }),
            .init(
              id: "answer", build: { buffer, context in buffer.text(Text("Answer").selectable(), context: context) }),
          ]), context: context)
      return node68
    }
    _ = producer.render(
      build: content, viewport: Size(width: 500, height: 500),
      input: InputState(), context: context, onChange: {})
    target.focus()
    _ = producer.render(
      build: content, viewport: Size(width: 500, height: 500),
      input: InputState(), context: context, onChange: {})
    #expect(target.isFocused)
    context.interaction.navigationPath = []
    context.interaction.selectAll(at: .zero)
    #expect(context.interaction.copyText() == "read_file\narguments\noutput\nAnswer")
  }
}
