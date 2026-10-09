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
    let context = LayoutContext()
    let metrics = context.fontMetrics
    let width = metrics.cellAdvance * 2
    let text = Text("abcd").wrapping().selectable()
    let size = text.sizeThatFits(Size(width: width, height: 100), context: context)
    #expect(size.height == metrics.lineAdvance * 2)
    let producer = FrameProducer()
    let list = producer.render(
      build: { buffer, context in buffer.text(text, context: context) }, viewport: size, input: InputState(),
      context: context, onChange: {})
    let strings = list.paintSnapshot.compactMap { command -> String? in
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

  @Test func editorInsertsNewlineAtCaretAndReplacesSelection() {
    let runtime = WindowRuntime()
    let context = runtime.context
    var text = "abcd"
    let editor = TextEditor(text: { text }, onChange: { text = $0 })
    runtime.build = { buffer, context in buffer.textEditor(editor, context: context) }
    func render(_ events: [TextEditEvent] = []) {
      _ = runtime.render(
        viewport: Size(width: 200, height: 100),
        input: InputState(textEvents: events),
        onChange: {})
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
    let runtime = WindowRuntime()
    let context = runtime.context
    var submitted: [String] = []
    var ended = 0
    let editor = TextEditor(
      text: { "draft" }, onChange: { _ in }, onSubmit: { submitted.append($0) },
      onEndEditing: {
        ended += 1
        return .handled
      })
    runtime.build = { buffer, context in buffer.textEditor(editor, context: context) }
    func render(_ events: [TextEditEvent] = []) {
      _ = runtime.render(
        viewport: Size(width: 200, height: 100),
        input: InputState(textEvents: events),
        onChange: {})
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
    let context = LayoutContext()
    struct Item: Identifiable { let id: Int }
    func render(_ ids: [Int]) {
      _ = producer.render(
        build: { buffer, context in
          buffer.scrollView(
            ScrollView(data: ids.map { Item(id: $0) }, rowHeight: 20, controller: controller) { buffer, context, item in
              buffer.text(Text(String(item.id)), context: context)
            }, context: context)
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

  @Test func rowRevealWaitsForMissingRow() {
    let controller = ScrollViewController()
    let producer = FrameProducer()
    let context = LayoutContext()
    struct Item: Identifiable { let id: Int }
    func render(_ ids: [Int]) {
      _ = producer.render(
        build: { buffer, context in
          buffer.scrollView(
            ScrollView(data: ids.map { Item(id: $0) }, rowHeight: 20, controller: controller) { buffer, context, item in
              buffer.text(Text(String(item.id)), context: context)
            }, context: context)
        }, viewport: Size(width: 200, height: 40), input: InputState(), context: context, onChange: {})
    }
    controller.scrollToRow(5)
    render([0, 1, 2, 3])
    #expect(controller.offset == 0)
    render([0, 1, 2, 3, 4, 5, 6])
    #expect(controller.offset == 100)
  }

  @Test func editorDragKeepsVisibleLinesStable() {
    let runtime = WindowRuntime()
    let context = runtime.context
    let text = "a\nb\nc\nd\ne"
    let editor = TextEditor(lineLimits: 2...2, text: { text }, onChange: { _ in })
    let line = context.fontMetrics.lineAdvance
    let height = 2 * line + 16
    runtime.build = { buffer, context in buffer.textEditor(editor, context: context) }
    func render(_ input: InputState = InputState()) -> DrawList {
      runtime.render(
        viewport: Size(width: 200, height: height),
        input: input,
        onChange: {})
    }
    _ = render()
    let id = context.interaction.tree!.firstLeafPath().flatMap { context.interaction.tree?.node(at: $0)?.leafID }!
    context.focus(id, editing: true)
    context.interaction.caretOffset = text.count
    _ = render()
    let start = Point(x: 8, y: 8 + line / 2)
    let end = Point(x: 8 + context.fontMetrics.cellAdvance, y: 8 + line * 1.5)
    _ = render(InputState(pointerPosition: start, pointerDown: true, pointerPressed: true))
    _ = render(InputState(pointerPosition: end, pointerDown: true))
    #expect(context.interaction.textSelectionRange == 6..<9)
    let held = render(InputState(pointerPosition: end, pointerDown: true))
    #expect(context.interaction.textSelectionRange == 6..<9)
    let lines = held.paintSnapshot.compactMap { command -> String? in
      if case .text(_, let text, _, _) = command { return text }
      return nil
    }
    #expect(lines.contains("d") && lines.contains("e"))
  }

  @Test func editorDragScrollsBeyondVisibleLines() {
    let runtime = WindowRuntime()
    let context = runtime.context
    let text = "a\nb\nc\nd\ne"
    let editor = TextEditor(lineLimits: 2...2, text: { text }, onChange: { _ in })
    let line = context.fontMetrics.lineAdvance
    let size = Size(width: 200, height: 2 * line + 16)
    runtime.build = { buffer, context in buffer.textEditor(editor, context: context) }
    func render(_ input: InputState = InputState()) {
      _ = runtime.render(
        viewport: size, input: input,
        onChange: {})
    }
    render()
    let start = Point(x: 8, y: 8 + line / 2)
    let below = Point(x: 8 + context.fontMetrics.cellAdvance, y: size.height + 1)
    render(InputState(pointerPosition: start, pointerDown: true, pointerPressed: true))
    for _ in 0..<4 { render(InputState(pointerPosition: below, pointerDown: true)) }
    #expect(context.interaction.textSelectionRange == 0..<text.count)
  }

  @Test func directTextNodesComposeWithLoopsAndLayout() {
    let content = ScrollView("Messages") { buffer, context in
      let headerContext = context.childScope(0)
      let header = buffer.text(Text("Header"), context: headerContext)
      var children = [buffer.padding(header, 2, context: headerContext)]
      for index in 0..<3 {
        children.append(buffer.text(Text("Message \(index)"), context: context.childScope(1).keyed(index)))
      }
      let showFooter = true
      if showFooter { children.append(buffer.text(Text("Footer"), context: context.childScope(2))) }
      return buffer.stack(children, axis: .vertical, context: context)
    }
    let context = LayoutContext()
    let list = FrameProducer().render(
      build: { buffer, context in buffer.scrollView(content, context: context) },
      viewport: Size(width: 200, height: 200),
      input: InputState(),
      context: context, onChange: {})
    let strings = list.paintSnapshot.compactMap { command -> String? in
      if case .text(_, let text, _, _) = command { return text }
      return nil
    }
    #expect(strings == ["Header", "Message 0", "Message 1", "Message 2", "Footer"])
    #expect(context.interaction.navigation?.children.first?.name == "Messages")
  }

  @Test func namedVirtualizedScrollUsesCurrentConfiguration() {
    let controller = ScrollViewController()
    controller.scrollToBottom()
    var view = ScrollView("History", data: 0..<100, rowHeight: 20, controller: controller) { buffer, context, row in
      buffer.text(Text("Row \(row)"), context: context)
    }
    view.showsIndicator = false
    let context = LayoutContext()
    let producer = FrameProducer()
    let list = producer.render(
      build: { buffer, context in buffer.scrollView(view, context: context) }, viewport: Size(width: 200, height: 40),
      input: InputState(), context: context, onChange: {})
    #expect(view.controller === controller)
    #expect(controller.offset == 1960)
    #expect(context.interaction.navigation?.children.first?.name == "History")
    let strings = list.paintSnapshot.compactMap { command -> String? in
      if case .text(_, let text, _, _) = command { return text }
      return nil
    }
    #expect(strings.contains("Row 99"))
    #expect(strings.count <= 3)
    _ = producer.render(
      build: { buffer, context in buffer.empty(context: context) }, viewport: Size(width: 200, height: 40),
      input: InputState(),
      context: context, onChange: {})
    #expect(context.interaction.scrollStates.isEmpty)
  }

  @Test func measuredRowsKeepControllerWhenCopied() {
    let controller = ScrollViewController()
    let view = ScrollView(
      controller: controller,
      rows: (0..<20).map { row in
        ScrollView.Row(id: row) { buffer, context in
          let text = buffer.text(Text("Row \(row)"), context: context)
          return buffer.sizing(text, y: .fixed(20), context: context)
        }
      })
    var copy = view
    copy.name = "Copied"
    copy.showsIndicator = false
    controller.scrollToBottom()
    let context = LayoutContext()
    _ = FrameProducer().render(
      build: { buffer, context in buffer.scrollView(copy, context: context) }, viewport: Size(width: 200, height: 40),
      input: InputState(),
      context: context, onChange: {})
    #expect(copy.controller === controller)
    #expect(view.controller === controller)
    #expect(controller.offset == 360)
    #expect(context.interaction.navigation?.children.first?.name == "Copied")
  }

  @Test func switchingToVerticalRowsClearsHorizontalOffset() {
    let controller = ScrollViewController()
    let runtime = WindowRuntime()
    let context = runtime.context
    let viewport = Size(width: 100, height: 40)
    let wide = ScrollView(controller: controller) { buffer, context in
      let color = buffer.color(.white, context: context)
      return buffer.sizing(color, x: .fixed(300), y: .fixed(100), context: context)
    }
    var content = wide
    runtime.build = { buffer, context in buffer.scrollView(content, context: context) }
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    _ = runtime.render(
      viewport: viewport,
      input: InputState(pointerPosition: Point(x: 20, y: 20), scrollDelta: Point(x: -50, y: 0)),
      onChange: {})
    #expect(controller.horizontalOffset == 50)
    let rows = ScrollView(data: 0..<20, rowHeight: 20, controller: controller) { buffer, context, row in
      buffer.text(Text("Row \(row)"), context: context)
    }
    content = rows
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    #expect(controller.horizontalOffset == 0)
    #expect(context.interaction.scrollStates.values.allSatisfy { $0.offset.x == 0 && $0.limit.x == 0 })
  }

}
