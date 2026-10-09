import ChromaTesting
import Testing

@testable import Chroma

@MainActor
struct TextSelectionPaintingTests {
  private struct SelectedRow {
    let row: Int
    let columns: Range<Int>
  }

  private func expectPainting(
    _ text: String, lines: [String], selection: Range<Int>, selectedRows: [SelectedRow],
    wraps: Bool = false, columns: Int = 20, scale: Float = 1
  ) {
    let context = LayoutContext()
    let metrics = context.fontMetrics
    let cell = metrics.cellAdvance * scale
    let height = metrics.lineAdvance * scale
    let rect = Rect(x: 13, y: 17, width: Float(columns) * cell, height: 400)
    let foreground = Color(r: 1, g: 0, b: 0, a: 1)
    let text = Text(text).foregroundColor(foreground).fontScale(scale).wrapping(wraps).selectable(context.widgetID)
    var buffer = LayoutBuffer()
    let node = buffer.text(text, context: context)
    context.interaction.beginFrame(input: InputState())
    buffer.register(node, in: rect)
    context.interaction.beginEditing(context.widgetID, caretOffset: selection.upperBound)
    context.interaction.textSelectionRange = selection
    let generation = context.interaction.editingSessionGeneration

    var expected = DrawList()
    for (row, line) in lines.enumerated() {
      expected.text(line, at: Point(x: rect.minX, y: rect.minY + Float(row) * height), color: foreground, scale: scale)
    }
    for selected in selectedRows {
      let origin = Point(x: rect.minX, y: rect.minY + Float(selected.row) * height)
      let highlight = Rect(
        x: origin.x + Float(selected.columns.lowerBound) * cell, y: origin.y,
        width: Float(selected.columns.count) * cell, height: height)
      expected.fillRect(highlight, color: context.theme.focus.selectionBackground)
      expected.pushClip(highlight)
      expected.text(lines[selected.row], at: origin, color: context.theme.focus.selectionForeground, scale: scale)
      expected.popClip()
    }
    for _ in 0..<2 {
      var actual = DrawList()
      buffer.paint(node, into: &actual, in: rect)
      #expect(actual.commands == expected.commands)
    }
    #expect(context.interaction.textSelectionRange == selection)
    #expect(context.interaction.caretOffset == selection.upperBound)
    #expect(context.interaction.editingSessionGeneration == generation)
    #expect(context.interaction.tree == nil)
    #expect(context.interaction.building.readOnlyTexts[context.widgetID] != nil)
    context.interaction.endFrame()
  }

  @Test func partialMultilineSelectionKeepsGeometryColorsAndPainterOrder() {
    expectPainting(
      "abcd\nefgh\nijkl", lines: ["abcd", "efgh", "ijkl"], selection: 2..<12,
      selectedRows: [.init(row: 0, columns: 2..<4), .init(row: 1, columns: 0..<4), .init(row: 2, columns: 0..<2)],
      scale: 1.5)
  }

  @Test func explicitNewlinesAndEmptyRowsDoNotPaintExtraForeground() {
    expectPainting(
      "ab\n\ncd\n", lines: ["ab", "", "cd", ""], selection: 1..<7,
      selectedRows: [.init(row: 0, columns: 1..<2), .init(row: 2, columns: 0..<2)])
    expectPainting("ab\ncd", lines: ["ab", "cd"], selection: 2..<3, selectedRows: [])
  }

  @Test func softWrapBoundariesAndUnicodeGraphemesKeepTheirColumns() {
    expectPainting(
      "a👨‍👩‍👧‍👦e\u{301}bcd", lines: ["a👨‍👩‍👧‍👦e\u{301}", "bcd"], selection: 1..<5,
      selectedRows: [.init(row: 0, columns: 1..<3), .init(row: 1, columns: 0..<2)],
      wraps: true, columns: 3)
    expectPainting(
      "abcdefghi", lines: ["abc", "def", "ghi"], selection: 3..<6,
      selectedRows: [.init(row: 1, columns: 0..<3)], wraps: true, columns: 3)
  }

  @Test func collapsedSelectionKeepsTheWrappedCaretPosition() {
    let context = LayoutContext()
    let cell = context.fontMetrics.cellAdvance
    let height = context.fontMetrics.lineAdvance
    let rect = Rect(x: 13, y: 17, width: 3 * cell, height: 200)
    var buffer = LayoutBuffer()
    let node = buffer.text(Text("abcdef").wrapping().selectable(context.widgetID), context: context)
    context.interaction.beginFrame(input: InputState())
    buffer.register(node, in: rect)
    context.interaction.beginEditing(context.widgetID, caretOffset: 4)
    var actual = DrawList()
    buffer.paint(node, into: &actual, in: rect)
    var expected = DrawList()
    expected.text("abc", at: rect.origin, color: .white)
    expected.text("def", at: Point(x: rect.minX, y: rect.minY + height), color: .white)
    expected.fillRect(
      Rect(x: rect.minX + cell, y: rect.minY + height, width: 1, height: height),
      color: context.theme.focus.ring)
    #expect(actual.commands == expected.commands)
    #expect(context.interaction.caretOffset == 4)
  }

  private func glyphCount(_ commands: [DrawEntry], color: Color? = nil) -> Int {
    commands.filter {
      guard case .quad(let quad) = $0, quad.texture == .fontAtlas else { return false }
      if let color { return quad.colors == CornerColors(color) }
      return true
    }.count
  }

  @Test func selectAllCommandGenerationScalesLinearly() {
    var counts: [Int] = []
    for lineCount in [10, 50, 100] {
      let host = HeadlessHost(size: Size(width: 800, height: 600))
      defer { host.close() }
      let target = FocusTarget()
      let text = Array(repeating: String(repeating: "a", count: 80), count: lineCount).joined(separator: "\n")
      host.build = { buffer, context in
        buffer.focus(target, context: context) { buffer, context in
          buffer.text(Text(text).selectable(), context: context)
        }
      }
      let before = host.render()
      target.focus()
      host.render()
      host.sendInput(InputState(commands: [.navigation(.stepIn)]))
      host.sendInput(InputState(textEvents: [.selectAll]))
      let selected = host.render()
      #expect(target.isFocused)
      #expect(host.interaction.copyText() == text)
      #expect(glyphCount(before.commands) == 80 * lineCount)
      #expect(glyphCount(selected.commands) == 160 * lineCount)
      #expect(selected.commands.count <= 2 * before.commands.count + 3 * lineCount + 5)
      counts.append(selected.commands.count)
    }
    // Compare slopes too, so neither fixed overhead nor timing noise hides quadratic work.
    #expect((counts[1] - counts[0]) * 50 == (counts[2] - counts[1]) * 40)
  }

  @Test func documentSelectionRedrawsEachRowOnlyOnceAndPreservesCopy() {
    let context = LayoutContext()
    let producer = FrameProducer()
    let build: LayoutBuilder = { buffer, context in
      let first = buffer.text(Text("ab\ncd").foregroundColor(.black).selectable(), context: context.childScope(0))
      let second = buffer.text(
        Text("e\u{301}f\n👨‍👩‍👧‍👦g").foregroundColor(.black).selectable(), context: context.childScope(1))
      return buffer.stack([first, second], axis: .vertical, context: context)
    }
    func render() -> DrawList {
      producer.render(
        build: build, viewport: Size(width: 400, height: 300),
        input: InputState(),
        context: context, onChange: {})
    }
    let before = render()
    context.interaction.navigationPath = []
    context.interaction.selectAll(at: .zero)
    #expect(context.interaction.copyText() == "ab\ncd\ne\u{301}f\n👨‍👩‍👧‍👦g")
    let selected = render()
    #expect(glyphCount(before.commands) == 8)
    #expect(glyphCount(selected.commands) == 16)
    #expect(glyphCount(selected.commands, color: context.theme.focus.selectionForeground) == 8)
  }
}
