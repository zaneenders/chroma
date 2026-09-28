import Testing

@testable import Chroma

@MainActor
struct ContentAPITests {
  @Test func wrappingPreservesGraphemesNewlinesAndOffsets() {
    let layout = TextLayout("a👨‍👩‍👧‍👦bc\n\nxy", columns: 2)
    #expect(layout.lines.map(\.text) == ["a👨‍👩‍👧‍👦", "bc", "", "xy"])
    #expect(layout.lines.map(\.range) == [0..<2, 2..<4, 5..<5, 6..<8])
    #expect(layout.row(containing: 2) == 1)
    #expect(layout.offset(row: 3, column: 99) == 8)
    #expect(layout.verticalOffset(3, direction: 1) == 5)
    #expect(TextLayout("ab\n", columns: 2).lines.map(\.text) == ["ab", ""])
    #expect(TextLayout("").lines.count == 1)
  }

  @Test func wrappedTextMeasurementDrawingAndSelectionAgree() {
    let context = BlockContext()
    let metrics = context.fontMetrics
    let width = metrics.cellAdvance * 2
    let text = Text("abcd").wrapping().selectable()
    let size = text.sizeThatFits(Size(width: width, height: 100), context: context)
    #expect(size.height == metrics.lineAdvance * 2)
    let producer = FrameProducer()
    let list = producer.render(
      content: text, viewport: size, input: InputState(), context: context, onChange: {})
    let strings = list.commands.compactMap { command -> String? in
      if case .text(_, let text, _, _) = command { return text }
      return nil
    }
    #expect(strings == ["ab", "cd"])
    let layout = PlainTextLayout(
      text: "abcd", rect: Rect(origin: .zero, size: size), cellWidth: metrics.cellAdvance,
      lineHeight: metrics.lineAdvance, scale: 1, columns: 2)
    #expect(layout.position(at: 2) == Point(x: 0, y: metrics.lineAdvance))
    #expect(layout.hitTest(point: Point(x: metrics.cellAdvance, y: metrics.lineAdvance)) == 3)
    #expect(layout.textInRange(from: 1, to: 3) == "bc")
  }

  @Test func spinnerDeadlinesCoalesceAndDisappearWithContent() {
    let producer = FrameProducer(clock: { 100 })
    let context = BlockContext()
    func render(_ content: any Block) {
      _ = producer.render(
        content: content, viewport: Size(width: 200, height: 40), input: InputState(),
        context: context, onChange: {})
    }
    render(
      HStack {
        ProgressIndicator()
        ProgressIndicator()
        ProgressIndicator()
        ProgressIndicator()
      })
    #expect(producer.nextAnimationDeadline == 1101.0 / 11)
    render(ProgressIndicator(isActive: false))
    #expect(producer.nextAnimationDeadline == nil)
    render(ProgressIndicator())
    producer.reset()
    #expect(producer.nextAnimationDeadline == nil)
  }

  @Test func earliestAnimationWins() {
    let context = BlockContext()
    context.interaction.animationFrame = AnimationFrame(timestamp: 100)
    context.requestAnimation(at: 102)
    context.requestAnimation(at: 101)
    context.requestAnimation(at: 103)
    #expect(context.interaction.nextAnimationDeadline == 101)
  }

  @Test func nonOverflowingMarqueeDoesNotAnimate() {
    let producer = FrameProducer(clock: { 100 })
    _ = producer.render(
      content: MarqueeText("short"), viewport: Size(width: 500, height: 40), input: InputState(),
      context: BlockContext(), onChange: {})
    #expect(producer.nextAnimationDeadline == nil)
  }

  @Test func editorInsertsNewlineAtCaretAndReplacesSelection() {
    let producer = FrameProducer()
    let context = BlockContext()
    var text = "abcd"
    let editor = TextEditor(text: { text }, onChange: { text = $0 })
    func render(_ events: [TextEditEvent] = []) {
      _ = producer.render(
        content: editor, viewport: Size(width: 200, height: 100), input: InputState(textEvents: events),
        context: context, onChange: {})
    }
    render()
    let id = context.interaction.tree!.firstLeafPath().flatMap { context.interaction.tree?.node(at: $0)?.leafID }!
    context.focus(id, editing: true)
    context.interaction.caretOffset = 2
    render([.submit])
    #expect(text == "ab\ncd")
    #expect(context.interaction.caretOffset == 3)
    context.interaction.textSelectionRange = 0..<3
    render([.submit])
    #expect(text == "\ncd")
    #expect(context.interaction.caretOffset == 1)
  }

  @Test func editorSubmitAndEndEditingCallbacksAreScoped() {
    let producer = FrameProducer()
    let context = BlockContext()
    var submitted: [String] = []
    var ended = 0
    let editor = TextEditor(
      text: { "draft" }, onChange: { _ in }, onSubmit: { submitted.append($0) },
      onEndEditing: {
        ended += 1
        return .handled
      })
    func render(_ events: [TextEditEvent] = []) {
      _ = producer.render(
        content: editor, viewport: Size(width: 200, height: 100), input: InputState(textEvents: events),
        context: context, onChange: {})
    }
    render()
    let id = context.interaction.tree!.firstLeafPath().flatMap { context.interaction.tree?.node(at: $0)?.leafID }!
    context.focus(id, editing: true)
    context.interaction.caretOffset = 0
    render([.submit, .endEditing])
    #expect(submitted == ["draft"])
    #expect(ended == 1)
    #expect(context.interaction.isTextEditing)
  }

  @Test func rowRevealUsesStableKeysAfterReordering() {
    let controller = ScrollViewController()
    let producer = FrameProducer()
    let context = BlockContext()
    struct Item: Identifiable { let id: Int }
    func render(_ ids: [Int]) {
      _ = producer.render(
        content: ScrollView(data: ids.map { Item(id: $0) }, rowHeight: 20, controller: controller) {
          Text(String($0.id))
        },
        viewport: Size(width: 200, height: 40), input: InputState(), context: context, onChange: {})
    }
    render(Array(0..<10))
    controller.scrollToRow(5)
    render(Array(0..<10))
    #expect(controller.offset == 100)
    controller.scrollToRow(5)
    render([0, 5, 1, 2, 3, 4, 6, 7, 8, 9])
    #expect(controller.offset == 20)
  }
}
