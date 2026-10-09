import Testing

@testable import Chroma

@MainActor
struct TextSelectionTests {

  private let text = "Session: AB12"
  private let cellWidth: Float = 8
  private let lineHeight: Float = 16

  private var layout: PlainTextLayout {
    PlainTextLayout(
      rect: Rect(
        x: 20, y: 20, width: cellWidth * Float(text.count), height: lineHeight),
      cellWidth: cellWidth, lineHeight: lineHeight, snapshot: TextLayoutSnapshot(text, columns: nil))
  }

  private func frame(_ ctx: Interaction, id: WidgetID, input: InputState) {
    func register() {
      let layout = layout
      _ = ctx.registerTextInput(
        id: id, rect: layout.rect, text: { text }, onChange: { _ in },
        pointerOffset: { point, _ in layout.selectionOffset(at: point) },
        verticalOffset: { layout.verticalOffset($0, direction: $1) },
        navigationIgnored: true, readOnly: true)
    }
    if ctx.tree == nil {
      ctx.beginFrame(input: InputState())
      register()
      ctx.endFrame()
    }
    beginTestFrame(ctx, input: input)
    register()
    ctx.endFrame()
  }

  @Test func selectingPlainTextEndsEditableSelection() {
    let runtime = WindowRuntime()
    let context = runtime.context
    var value = "editable"
    runtime.build = { buffer, context in
      let label = buffer.text(Text("selectable").selectable(), context: context.childScope(0))
      let editor = buffer.textEditor(
        TextEditor(singleLine: true, text: { value }, onChange: { value = $0 }), context: context.childScope(1))
      return buffer.stack([label, editor], axis: .vertical, context: context)
    }
    func render(_ input: InputState = InputState()) {
      _ = runtime.render(
        viewport: Size(width: 300, height: 150),
        input: input, onChange: {})
    }
    render()
    render(InputState(pointerPosition: Point(x: 10, y: 40), pointerDown: true, pointerPressed: true))
    render(InputState(pointerPosition: Point(x: 46, y: 40), pointerReleased: true))
    #expect(context.interaction.editableSelectionText() == "edi")
    render(InputState(pointerPosition: Point(x: 0, y: 10), pointerDown: true, pointerPressed: true))
    render(InputState(pointerPosition: Point(x: 36, y: 10), pointerReleased: true))
    #expect(context.interaction.editingReadOnly)
    #expect(context.interaction.textSelectionRange == 0..<3)
    #expect(context.interaction.copyText() == "sel")
    render(InputState(textEvents: [.insert("X")]))
    #expect(value == "editable")
  }

  @Test func beginningEditingClearsPlainTextSelection() {
    let ctx = Interaction()
    let id = WidgetID("plain")
    frame(ctx, id: id, input: InputState())
    ctx.selectAll(at: Point(x: 21, y: 21))
    #expect(ctx.copyText() == text)
    ctx.beginEditing(WidgetID("field"), caretOffset: 0)
    #expect(ctx.copyText() == nil)
  }

  @Test func hitTestSnapsToNearestBoundary() {
    let l = layout
    #expect(l.hitTest(point: Point(x: l.rect.minX + 1, y: 21)) == 0)
    #expect(l.hitTest(point: Point(x: l.rect.minX + cellWidth - 1, y: 21)) == 1)
    #expect(l.hitTest(point: Point(x: l.rect.maxX - cellWidth / 4, y: 21)) == text.utf8.count)
    #expect(l.hitTest(point: Point(x: l.rect.maxX - cellWidth + 1, y: 21)) == text.utf8.count - 1)
    #expect(l.hitTest(point: Point(x: l.rect.maxX, y: 21)) == nil)
    #expect(l.hitTest(point: Point(x: l.rect.minX - 1, y: 21)) == nil)
  }

  @Test func dragIntoLastCellSelectsEntireText() {
    let ctx = Interaction()
    let id = WidgetID("session-id")
    let l = layout

    let origin = Point(x: l.rect.minX + 1, y: 21)
    frame(
      ctx, id: id,
      input: InputState(
        pointerPosition: origin, pointerPressPosition: origin,
        pointerDown: true, pointerPressed: true))
    let move = InputState(
      pointerPosition: Point(x: l.rect.maxX - cellWidth / 4, y: 21),
      pointerDown: true)
    frame(ctx, id: id, input: move)
    frame(ctx, id: id, input: move)

    #expect(ctx.copyText() == text)
  }

  @Test func dragPastEndSelectsEntireText() {
    let ctx = Interaction()
    let id = WidgetID("session-id")
    let l = layout

    let origin = Point(x: l.rect.minX + 1, y: 21)
    frame(
      ctx, id: id,
      input: InputState(
        pointerPosition: origin, pointerPressPosition: origin,
        pointerDown: true, pointerPressed: true))
    let move = InputState(
      pointerPosition: Point(x: l.rect.maxX + 40, y: 21),
      pointerDown: true)
    frame(ctx, id: id, input: move)
    frame(ctx, id: id, input: move)

    #expect(ctx.copyText() == text)
  }

  @Test func dragBelowLineSelectsToEnd() {
    let ctx = Interaction()
    let id = WidgetID("session-id")
    let l = layout

    let origin = Point(x: l.rect.minX + 1, y: 21)
    frame(
      ctx, id: id,
      input: InputState(
        pointerPosition: origin, pointerPressPosition: origin,
        pointerDown: true, pointerPressed: true))
    let move = InputState(
      pointerPosition: Point(x: l.rect.minX + 3 * cellWidth, y: l.rect.maxY + 10),
      pointerDown: true)
    frame(ctx, id: id, input: move)
    frame(ctx, id: id, input: move)

    #expect(ctx.copyText() == text)
  }

  @Test func partialDragSelectsPartialText() {
    let ctx = Interaction()
    let id = WidgetID("session-id")
    let l = layout

    let origin = Point(x: l.rect.minX + 1, y: 21)
    frame(
      ctx, id: id,
      input: InputState(
        pointerPosition: origin, pointerPressPosition: origin,
        pointerDown: true, pointerPressed: true))
    let move = InputState(
      pointerPosition: Point(x: l.rect.minX + 3 * cellWidth + 1, y: 21),
      pointerDown: true)
    frame(ctx, id: id, input: move)
    frame(ctx, id: id, input: move)

    #expect(ctx.copyText() == "Ses")
  }

  @Test func unicodeLayoutUsesGraphemeBoundaries() {
    let unicode = "A👨‍👩‍👧‍👦e\u{301}🇺🇸"
    let l = PlainTextLayout(
      rect: Rect(x: 0, y: 0, width: cellWidth * Float(unicode.count), height: lineHeight),
      cellWidth: cellWidth, lineHeight: lineHeight, snapshot: TextLayoutSnapshot(unicode, columns: nil))

    #expect(unicode.count == 4)
    #expect(l.hitTest(point: Point(x: cellWidth * 2, y: 1)) == 2)
    #expect(l.selectionOffset(at: Point(x: 100, y: 1)) == 4)
    #expect(l.selectionOffset(at: Point(x: -10, y: 1)) == 0)
  }

  @Test func fontMetricsMeasureRenderedCharactersNotUTF8Bytes() {
    let metrics = FontMetrics()
    #expect(metrics.measure("ASCII").width == metrics.cellAdvance * 5)
    #expect(metrics.measure("👨‍👩‍👧‍👦e\u{301}🇺🇸").width == metrics.cellAdvance * 3)
    #expect(metrics.measure("ASCII", scale: 2).width == metrics.cellAdvance * 10)
  }

  @Test func invalidCellWidthsDoNotTrapDuringHitTesting() {
    for width in [Float.zero, -Float.infinity, Float.infinity, Float.nan] {
      let l = PlainTextLayout(
        rect: Rect(x: 0, y: 0, width: 20, height: 20),
        cellWidth: width, lineHeight: 20, snapshot: TextLayoutSnapshot("abc", columns: nil))
      #expect(l.hitTest(point: Point(x: 1, y: 1)) == nil)
    }
  }

  @Test func copyTextFallsBackToTheActiveTextSelection() {
    let ctx = Interaction()
    let id = WidgetID("copy-source")
    let l = layout
    let origin = Point(x: l.rect.minX + 1, y: 21)

    frame(
      ctx, id: id,
      input: InputState(
        pointerPosition: origin, pointerPressPosition: origin,
        pointerDown: true, pointerPressed: true))
    let move = InputState(
      pointerPosition: Point(x: l.rect.minX + 3 * cellWidth + 1, y: 21),
      pointerDown: true)
    frame(ctx, id: id, input: move)
    frame(ctx, id: id, input: move)

    #expect(ctx.copyText() == "Ses")
  }

  @Test func selectAllExpandsTheActiveSelection() {
    let ctx = Interaction()
    let id = WidgetID("copy-source")
    let l = layout
    let origin = Point(x: l.rect.minX + cellWidth, y: 21)

    frame(
      ctx, id: id,
      input: InputState(
        pointerPosition: origin, pointerPressPosition: origin,
        pointerDown: true, pointerPressed: true))
    let move = InputState(
      pointerPosition: Point(x: l.rect.minX + 3 * cellWidth, y: 21),
      pointerDown: true)
    frame(ctx, id: id, input: move)
    frame(ctx, id: id, input: move)

    ctx.selectAll(at: .zero)

    #expect(ctx.copyText() == text)
  }

  @Test func registeredProvidersReplacePriorValuesAndDisappearOnRemoval() {
    let context = LayoutContext()
    var handled: [String] = []
    for value in ["first", "second"] {
      context.interaction.beginFrame(input: InputState())
      context.setCopyTextProvider { value }
      context.setSelectAllHandler {
        handled.append(value)
        return true
      }
      context.interaction.endFrame()
      #expect(context.interaction.copyText() == value)
      context.interaction.selectAll(at: .zero)
    }
    #expect(handled == ["first", "second"])
    context.interaction.beginFrame(input: InputState())
    context.interaction.endFrame()
    #expect(context.interaction.copyText() == nil)
    context.interaction.selectAll(at: .zero)
    #expect(handled == ["first", "second"])
  }

  @Test func contextsTrackSelectionsIndependently() {
    let a = Interaction()
    let b = Interaction()
    let id = WidgetID("session-id")
    let l = layout

    let origin = Point(x: l.rect.minX + 1, y: 21)
    frame(
      a, id: id,
      input: InputState(
        pointerPosition: origin, pointerPressPosition: origin,
        pointerDown: true, pointerPressed: true))
    let move = InputState(
      pointerPosition: Point(x: l.rect.maxX - cellWidth / 4, y: 21),
      pointerDown: true)
    frame(a, id: id, input: move)
    frame(a, id: id, input: move)

    #expect(a.copyText() == text)
    #expect(b.copyText() == nil)
    #expect(a.isDragging)
    #expect(!b.isDragging)
  }
}
