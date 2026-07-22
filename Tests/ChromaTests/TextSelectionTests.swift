import Testing
@testable import Chroma

/// Tests for drag-based plain-text selection (`Text.selectable`).
///
/// End-to-end tests drive `Interaction` the way the backend does:
/// `beginFrame` (carrying input) updates the selection from the layouts
/// registered during the *previous* frame, then the test re-registers the
/// layout to simulate the draw pass.
@MainActor
@Suite(.serialized)
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

  /// Runs one frame: input first (selection reads last frame's layouts),
  /// then a simulated draw re-registering the layout.
  private func frame(_ ctx: Interaction, id: WidgetID, input: InputState) {
    ctx.beginFrame(input: input)
    PlainTextLayoutRegistry.register(id, layout: layout)
    ctx.endFrame()
  }

  // MARK: Hit testing

  /// The selection end is exclusive, so reaching the last character requires
  /// the end index `text.count`. With `Rect.contains` excluding `maxX`, a
  /// flooring hit test could never produce it — the trailing half of the
  /// final cell must snap to the end boundary.
  @Test func hitTestSnapsToNearestBoundary() {
    let l = layout
    // First cell: leading half → before the character, trailing half → after.
    #expect(l.hitTest(point: Point(x: l.rect.minX + 1, y: 21)) == 0)
    #expect(l.hitTest(point: Point(x: l.rect.minX + cellWidth - 1, y: 21)) == 1)
    // Last cell: trailing half reaches the end index.
    #expect(l.hitTest(point: Point(x: l.rect.maxX - cellWidth / 4, y: 21)) == text.utf8.count)
    #expect(l.hitTest(point: Point(x: l.rect.maxX - cellWidth + 1, y: 21)) == text.utf8.count - 1)
    // Outside the rect is not a hit.
    #expect(l.hitTest(point: Point(x: l.rect.maxX, y: 21)) == nil)
    #expect(l.hitTest(point: Point(x: l.rect.minX - 1, y: 21)) == nil)
  }

  // MARK: Drag selection

  /// Regression: dragging from the start of the text into the last cell must
  /// select the entire string, including the final character.
  @Test func dragIntoLastCellSelectsEntireText() {
    let ctx = Interaction()
    Interaction.current = ctx
    defer { Interaction.current = Interaction() }
    TextSelectionManager.shared.clear()
    let id = WidgetID("session-id")
    let l = layout

    let origin = Point(x: l.rect.minX + 1, y: 21)
    frame(
      ctx, id: id,
      input: InputState(
        pointerPosition: origin, pointerPressPosition: origin,
        pointerDown: true, pointerPressed: true))
    // `dragCurrent` trails the pointer by a frame: the selection update at
    // the top of `beginFrame` reads the position latched by the previous
    // frame's `beginFrame`, so the move must be presented twice.
    let move = InputState(
      pointerPosition: Point(x: l.rect.maxX - cellWidth / 4, y: 21),
      pointerDown: true)
    frame(ctx, id: id, input: move)
    frame(ctx, id: id, input: move)

    #expect(TextSelectionManager.shared.selectedText() == text)
  }

  /// Dragging horizontally past the end of the text (leaving the rect on the
  /// same line) clamps the selection to the end.
  @Test func dragPastEndSelectsEntireText() {
    let ctx = Interaction()
    Interaction.current = ctx
    defer { Interaction.current = Interaction() }
    TextSelectionManager.shared.clear()
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

    #expect(TextSelectionManager.shared.selectedText() == text)
  }

  /// Dragging below the line still selects through the end.
  @Test func dragBelowLineSelectsToEnd() {
    let ctx = Interaction()
    Interaction.current = ctx
    defer { Interaction.current = Interaction() }
    TextSelectionManager.shared.clear()
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

    #expect(TextSelectionManager.shared.selectedText() == text)
  }

  /// A short drag stays a partial selection: snapping must not over-extend
  /// the highlighted range.
  @Test func partialDragSelectsPartialText() {
    let ctx = Interaction()
    Interaction.current = ctx
    defer { Interaction.current = Interaction() }
    TextSelectionManager.shared.clear()
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

    #expect(TextSelectionManager.shared.selectedText() == "Ses")
  }
}
