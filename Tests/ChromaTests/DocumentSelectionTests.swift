import Testing

@testable import Chroma

@MainActor
struct DocumentSelectionTests {
  @Test func selectionCrossesTextLeavesInDepthFirstOrderAndShrinks() {
    let context = BlockContext()
    let producer = FrameProducer()
    let first = FocusTarget()
    let content = Group("Session") {
      Text("ab").selectable().focusTarget(first)
      Group("Nested") { Text("café").selectable() }
      Text("end").selectable()
    }
    func render(_ events: [TextEditEvent] = [], commands: [Command] = []) {
      _ = producer.render(
        build: { buffer, context in buffer.emit(content, context: context) }, viewport: Size(width: 500, height: 500),
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
    let context = BlockContext()
    let producer = FrameProducer()
    let first = FocusTarget()
    let content = VStack {
      Group("Session") {
        Text("one").selectable().focusTarget(first)
        Text("two").selectable()
      }
      Text("outside").selectable()
      TextEditor(text: { "private draft" }, onChange: { _ in })
    }
    func render(_ commands: [Command] = []) {
      _ = producer.render(
        build: { buffer, context in buffer.emit(content, context: context) }, viewport: Size(width: 500, height: 500),
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
    let context = BlockContext()
    let producer = FrameProducer()
    let target = FocusTarget()
    let content = ScrollView(
      controller: ScrollViewController(),
      rows: [
        .init(
          id: "tool",
          content: VStack {
            Text("read_file").selectable().focusTarget(target)
            Text("arguments\noutput").selectable()
          }),
        .init(id: "answer", content: Text("Answer").selectable()),
      ])
    _ = producer.render(
      build: { buffer, context in buffer.emit(content, context: context) }, viewport: Size(width: 500, height: 500),
      input: InputState(), context: context, onChange: {})
    target.focus()
    _ = producer.render(
      build: { buffer, context in buffer.emit(content, context: context) }, viewport: Size(width: 500, height: 500),
      input: InputState(), context: context, onChange: {})
    #expect(target.isFocused)
    context.interaction.navigationPath = []
    context.interaction.selectAll(at: .zero)
    #expect(context.interaction.copyText() == "read_file\narguments\noutput\nAnswer")
  }
}
