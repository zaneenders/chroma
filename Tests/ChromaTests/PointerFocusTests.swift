import Testing

@testable import Chroma

@MainActor
struct PointerFocusTests {

  private static func drawFixture(_ ctx: Interaction, states: inout [WidgetID: ButtonState]) {
    ctx.beginGroup(rect: Rect(x: 0, y: 0, width: 100, height: 60))
    states[WidgetID("a")] = ctx.interactiveBehavior(
      id: WidgetID("a"), rect: Rect(x: 0, y: 0, width: 100, height: 20))
    states[WidgetID("b")] = ctx.interactiveBehavior(
      id: WidgetID("b"), rect: Rect(x: 0, y: 20, width: 100, height: 20))
    ctx.beginGroup(rect: Rect(x: 0, y: 40, width: 100, height: 20))
    states[WidgetID("c")] = ctx.interactiveBehavior(
      id: WidgetID("c"), rect: Rect(x: 0, y: 40, width: 50, height: 20))
    states[WidgetID("d")] = ctx.interactiveBehavior(
      id: WidgetID("d"), rect: Rect(x: 50, y: 40, width: 50, height: 20))
    ctx.endGroup()
    ctx.endGroup()
  }

  @discardableResult
  private func frame(
    _ ctx: Interaction,
    input: InputState = InputState(),
    draw: @MainActor (Interaction, inout [WidgetID: ButtonState]) -> Void = drawFixture
  ) -> [WidgetID: ButtonState] {
    let isInitialFrame = ctx.tree == nil
    ctx.beginFrame(input: input)
    var states: [WidgetID: ButtonState] = [:]
    draw(ctx, &states)
    ctx.endFrame()
    if isInitialFrame { ctx.focusFirstControlForTest() }
    return states
  }

  @Test func explicitFixtureFocusSelectsFirstLeaf() {
    let ctx = Interaction()
    frame(ctx)
    #expect(ctx.selection == [0, 0])
  }

  @Test func activateClicksSelectedLeaf() {
    let ctx = Interaction()
    frame(ctx)
    ctx.focus(WidgetID("b"))
    let states = frame(ctx, input: InputState(commands: [.action(.activate)]))
    #expect(states[WidgetID("b")]?.clicked == true)
    #expect(states[WidgetID("b")]?.focused == true)
    #expect(states[WidgetID("b")]?.hovered == false)
    #expect(states[WidgetID("a")]?.clicked == false)
    #expect(states[WidgetID("a")]?.focused == false)
  }

  @Test func hoverDoesNotMoveFocus() {
    let ctx = Interaction()
    frame(ctx)
    let states = frame(ctx, input: InputState(pointerPosition: Point(x: 75, y: 50)))
    #expect(ctx.selection == [0, 0])
    #expect(states[WidgetID("d")]?.hovered == true)
    #expect(states[WidgetID("d")]?.focused == false)
    #expect(states[WidgetID("a")]?.focused == true)
  }

  @Test func parkedPointerPreservesProgrammaticFocus() {
    let ctx = Interaction()
    frame(ctx)
    frame(ctx, input: InputState(pointerPosition: Point(x: 75, y: 50)))
    ctx.focus(WidgetID("b"))
    frame(ctx, input: InputState(pointerPosition: Point(x: 75, y: 50)))
    #expect(ctx.selection == [0, 1])
  }

  @Test func clickSelectsThenActivates() {
    let ctx = Interaction()
    frame(ctx)
    var states = frame(
      ctx,
      input: InputState(
        pointerPosition: Point(x: 25, y: 50), pointerDown: true, pointerPressed: true))
    #expect(ctx.selection == [0, 2, 0], "press moved the cursor to c")
    #expect(states[WidgetID("c")]?.held == true)
    #expect(states[WidgetID("c")]?.clicked == false)
    states = frame(
      ctx,
      input: InputState(pointerPosition: Point(x: 25, y: 50), pointerReleased: true))
    #expect(states[WidgetID("c")]?.clicked == true)
    #expect(states[WidgetID("c")]?.held == false)
  }

  @Test func batchedPressAndReleaseUsesPressPosition() {
    let ctx = Interaction()
    frame(ctx)
    let states = frame(
      ctx,
      input: InputState(
        pointerPosition: Point(x: 25, y: 30),
        pointerPressPosition: Point(x: 25, y: 10),
        pointerPressed: true, pointerReleased: true))
    #expect(ctx.selection == [0, 0])
    #expect(states.values.allSatisfy { !$0.clicked })
  }

  @Test func batchedPressAndReleaseOnSameControlClicks() {
    let ctx = Interaction()
    frame(ctx)
    let states = frame(
      ctx,
      input: InputState(
        pointerPosition: Point(x: 25, y: 30),
        pointerPressPosition: Point(x: 20, y: 25),
        pointerPressed: true, pointerReleased: true))
    #expect(states[WidgetID("b")]?.clicked == true)
  }

  @Test func omittedPressPositionDefaultsToPointerPosition() {
    let point = Point(x: 25, y: 30)
    #expect(InputState(pointerPosition: point, pointerPressed: true).pointerPressPosition == point)
  }

  @Test func pressInsideReleaseOutsideDoesNotClick() {
    let ctx = Interaction()
    frame(ctx)
    frame(
      ctx,
      input: InputState(
        pointerPosition: Point(x: 25, y: 50), pointerDown: true, pointerPressed: true))
    let states = frame(
      ctx,
      input: InputState(pointerPosition: Point(x: 500, y: 500), pointerReleased: true))
    #expect(states[WidgetID("c")]?.clicked == false)
    #expect(ctx.selection == [0, 2, 0], "releasing over empty space leaves the cursor")
  }

  @Test func overlappingLeavesTopMostWins() {
    let ctx = Interaction()
    frame(ctx) { ctx, states in
      ctx.beginGroup(rect: Rect(x: 0, y: 0, width: 100, height: 100))
      states[WidgetID("back")] = ctx.interactiveBehavior(
        id: WidgetID("back"), rect: Rect(x: 0, y: 0, width: 100, height: 100))
      states[WidgetID("front")] = ctx.interactiveBehavior(
        id: WidgetID("front"), rect: Rect(x: 0, y: 0, width: 100, height: 100))
      ctx.endGroup()
    }
    frame(ctx, input: InputState(pointerPosition: Point(x: 50, y: 50))) { ctx, states in
      ctx.beginGroup(rect: Rect(x: 0, y: 0, width: 100, height: 100))
      states[WidgetID("back")] = ctx.interactiveBehavior(
        id: WidgetID("back"), rect: Rect(x: 0, y: 0, width: 100, height: 100))
      states[WidgetID("front")] = ctx.interactiveBehavior(
        id: WidgetID("front"), rect: Rect(x: 0, y: 0, width: 100, height: 100))
      ctx.endGroup()
    }
    #expect(ctx.selection == [0, 0])
    #expect(ctx.hoveredLeafID == WidgetID("front"))
  }

  @Test func emptyGroupsArePruned() {
    let ctx = Interaction()
    var innerRetained = true
    var outerRetained = true
    frame(ctx) { ctx, states in
      ctx.beginGroup(rect: Rect(x: 0, y: 0, width: 100, height: 100))
      ctx.beginGroup(rect: Rect(x: 0, y: 0, width: 100, height: 50))
      ctx.beginGroup(rect: Rect(x: 0, y: 0, width: 50, height: 50))
      innerRetained = ctx.endGroup()
      outerRetained = ctx.endGroup()
      states[WidgetID("a")] = ctx.interactiveBehavior(
        id: WidgetID("a"), rect: Rect(x: 0, y: 50, width: 100, height: 50))
      ctx.endGroup()
    }
    #expect(!innerRetained)
    #expect(!outerRetained)
    #expect(ctx.selection == [0, 0], "the pruned groups occupy no path slots")
  }

  @Test func cursorFollowsWidgetIDAcrossRelayout() {
    let ctx = Interaction()
    frame(ctx)
    ctx.focus(WidgetID("b"))
    #expect(ctx.selection == [0, 1])
    frame(ctx) { ctx, states in
      ctx.beginGroup(rect: Rect(x: 0, y: 0, width: 100, height: 80))
      states[WidgetID("a")] = ctx.interactiveBehavior(
        id: WidgetID("a"), rect: Rect(x: 0, y: 0, width: 100, height: 20))
      states[WidgetID("x")] = ctx.interactiveBehavior(
        id: WidgetID("x"), rect: Rect(x: 0, y: 20, width: 100, height: 20))
      states[WidgetID("b")] = ctx.interactiveBehavior(
        id: WidgetID("b"), rect: Rect(x: 0, y: 40, width: 100, height: 20))
      ctx.endGroup()
    }
    #expect(ctx.selection == [0, 2], "cursor stayed on b")
  }

  @Test func focusFallsBackPredictablyAfterCompleteTreeReplacement() {
    let ctx = Interaction()
    frame(ctx)
    ctx.focus(WidgetID("b"))
    #expect(ctx.selection == [0, 1])

    frame(ctx) { ctx, states in
      ctx.beginGroup(rect: Rect(x: 0, y: 0, width: 100, height: 40))
      states[WidgetID("new-a")] = ctx.interactiveBehavior(
        id: WidgetID("new-a"), rect: Rect(x: 0, y: 0, width: 100, height: 20))
      states[WidgetID("new-b")] = ctx.interactiveBehavior(
        id: WidgetID("new-b"), rect: Rect(x: 0, y: 20, width: 100, height: 20))
      ctx.endGroup()
    }
    #expect(ctx.selection == [0, 1], "without a matching ID, the prior structural path is retained")
  }

  @Test func cursorClampsWhenLeafDisappears() {
    let ctx = Interaction()
    frame(ctx)
    ctx.focus(WidgetID("d"))
    #expect(ctx.selection == [0, 2, 1])
    frame(ctx) { ctx, states in
      ctx.beginGroup(rect: Rect(x: 0, y: 0, width: 100, height: 40))
      states[WidgetID("a")] = ctx.interactiveBehavior(
        id: WidgetID("a"), rect: Rect(x: 0, y: 0, width: 100, height: 20))
      states[WidgetID("b")] = ctx.interactiveBehavior(
        id: WidgetID("b"), rect: Rect(x: 0, y: 20, width: 100, height: 20))
      ctx.endGroup()
    }
    #expect(ctx.selection == [0, 1], "clamped to the last valid sibling")
  }

  @Test func scrollOutsideScrollViewDoesNotMoveFocus() {
    let ctx = Interaction()
    frame(ctx)
    ctx.focus(WidgetID("d"))
    for delta: Float in [1, -3] {
      frame(ctx, input: InputState(scrollDelta: Point(x: 0, y: delta)))
      #expect(ctx.selection == [0, 2, 1])
    }
  }
}
