import Testing
@testable import Chroma

@MainActor
struct TextSelectionTests {

  private let text = "Session: AB12"
  private let cellWidth: Float = 8
  private let lineHeight: Float = 16

  private var layout: PlainTextLayout {
    PlainTextLayout(
      text: text,
      rect: Rect(
        x: 20, y: 20, width: cellWidth * Float(text.utf8.count), height: lineHeight),
      cellWidth: cellWidth, lineHeight: lineHeight, scale: 1)
  }

  private func frame(_ ctx: Interaction, id: WidgetID, input: InputState) {
    ctx.beginFrame(input: input)
    ctx.textSelection.layoutRegistry.register(id, layout: layout)
    ctx.endFrame()
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

    #expect(ctx.textSelection.selectedText() == text)
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

    #expect(ctx.textSelection.selectedText() == text)
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

    #expect(ctx.textSelection.selectedText() == text)
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

    #expect(ctx.textSelection.selectedText() == "Ses")
  }


  @Test func unicodeLayoutUsesGraphemeBoundaries() {
    let unicode = "A👨‍👩‍👧‍👦e\u{301}🇺🇸"
    let l = PlainTextLayout(
      text: unicode,
      rect: Rect(x: 0, y: 0, width: cellWidth * Float(unicode.count), height: lineHeight),
      cellWidth: cellWidth, lineHeight: lineHeight, scale: 1)

    #expect(unicode.count == 4)
    #expect(l.hitTest(point: Point(x: cellWidth * 2, y: 1)) == 2)
    #expect(l.textInRange(from: 1, to: 2) == "👨‍👩‍👧‍👦")
    #expect(l.textInRange(from: 2, to: 3) == "e\u{301}")
    #expect(l.textInRange(from: 3, to: 4) == "🇺🇸")
    #expect(l.textInRange(from: -10, to: 100) == unicode)
  }

  @Test func fontMetricsMeasureRenderedCharactersNotUTF8Bytes() {
    let metrics = FontMetrics()
    #expect(metrics.measure("ASCII").width == metrics.cellAdvance * 5)
    #expect(metrics.measure("👨‍👩‍👧‍👦e\u{301}🇺🇸").width == metrics.cellAdvance * 3)
  }

  @Test func invalidCellWidthsDoNotTrapDuringHitTesting() {
    for width in [Float.zero, -Float.infinity, Float.infinity, Float.nan] {
      let l = PlainTextLayout(
        text: "abc", rect: Rect(x: 0, y: 0, width: 20, height: 20),
        cellWidth: width, lineHeight: 20, scale: 1)
      #expect(l.hitTest(point: Point(x: 1, y: 1)) == nil)
    }
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

    #expect(a.textSelection.selectedText() == text)
    #expect(b.textSelection.selectedText() == nil)
    #expect(a.textSelection.isSelecting)
    #expect(!b.textSelection.isSelecting)
  }
}
