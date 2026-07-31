import Testing
@testable import Chroma

@MainActor
struct NavigationTests {


  private static func drawFixture(_ ctx: Interaction, states: inout [WidgetID: ButtonState]) {
    ctx.beginGroup(.vertical, rect: Rect(x: 0, y: 0, width: 100, height: 60))
    states[WidgetID("a")] = ctx.interactiveBehavior(
      id: WidgetID("a"), rect: Rect(x: 0, y: 0, width: 100, height: 20))
    states[WidgetID("b")] = ctx.interactiveBehavior(
      id: WidgetID("b"), rect: Rect(x: 0, y: 20, width: 100, height: 20))
    ctx.beginGroup(.horizontal, rect: Rect(x: 0, y: 40, width: 100, height: 20))
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
    ctx.beginFrame(input: input)
    var states: [WidgetID: ButtonState] = [:]
    draw(ctx, &states)
    ctx.endFrame()
    return states
  }

  private func select(_ ctx: Interaction, _ commands: [UICommand]) {
    frame(ctx)
    for command in commands {
      frame(ctx, input: InputState(commands: [command]))
    }
  }


  @Test func firstFrameSelectsFirstLeaf() {
    let ctx = Interaction()
    frame(ctx)
    #expect(ctx.selection == [0, 0])
  }

  @Test func verticalMovementWalksAndStops() {
    let ctx = Interaction()
    select(ctx, [.down])
    #expect(ctx.selection == [0, 1])
    select(ctx, [.down])
    #expect(ctx.selection == [0, 2], "the horizontal row group is a sibling")
    select(ctx, [.down])
    #expect(ctx.selection == [0, 2], "past the last sibling the cursor stays put")
    select(ctx, [.up, .up])
    #expect(ctx.selection == [0, 0])
    select(ctx, [.up])
    #expect(ctx.selection == [0, 0], "before the first sibling the cursor stays put")
  }

  @Test func inAndOutCrossLevels() {
    let ctx = Interaction()
    select(ctx, [.down, .down])
    #expect(ctx.selection == [0, 2])
    select(ctx, [.in])
    #expect(ctx.selection == [0, 2, 0])
    select(ctx, [.out])
    #expect(ctx.selection == [0, 2])
    select(ctx, [.out, .out])
    #expect(ctx.selection == [], "out climbs to the root group")
    select(ctx, [.out])
    #expect(ctx.selection == [], "out at the root stays put")
  }

  @Test func horizontalMovementBubblesAndStops() {
    let ctx = Interaction()
    select(ctx, [.down, .down, .in, .right])
    #expect(ctx.selection == [0, 2, 1])
    select(ctx, [.left])
    #expect(ctx.selection == [0, 2, 0], "a plain sibling move still applies within the row")
    select(ctx, [.right, .right])
    #expect(ctx.selection == [0, 2, 1], "past the last sibling the cursor stays put")
    select(ctx, [.down])
    #expect(
      ctx.selection == [0, 2, 1],
      "down bubbles to the root, finds no next sibling, and stays put")
  }

  @Test func movementBubblesUpToTheNextSubtree() {
    let ctx = Interaction()
    let drawTwoRows: @MainActor (Interaction, inout [WidgetID: ButtonState]) -> Void = { ctx, states in
      ctx.beginGroup(.vertical, rect: Rect(x: 0, y: 0, width: 100, height: 40))
      ctx.beginGroup(.horizontal, rect: Rect(x: 0, y: 0, width: 100, height: 20))
      states[WidgetID("a")] = ctx.interactiveBehavior(
        id: WidgetID("a"), rect: Rect(x: 0, y: 0, width: 50, height: 20))
      states[WidgetID("b")] = ctx.interactiveBehavior(
        id: WidgetID("b"), rect: Rect(x: 50, y: 0, width: 50, height: 20))
      ctx.endGroup()
      ctx.beginGroup(.horizontal, rect: Rect(x: 0, y: 20, width: 100, height: 20))
      states[WidgetID("c")] = ctx.interactiveBehavior(
        id: WidgetID("c"), rect: Rect(x: 0, y: 20, width: 50, height: 20))
      states[WidgetID("d")] = ctx.interactiveBehavior(
        id: WidgetID("d"), rect: Rect(x: 50, y: 20, width: 50, height: 20))
      ctx.endGroup()
      ctx.endGroup()
    }
    frame(ctx, draw: drawTwoRows)
    #expect(ctx.selection == [0, 0, 0], "cursor starts on a")
    frame(ctx, input: InputState(commands: [.down]), draw: drawTwoRows)
    #expect(ctx.selection == [0, 1, 0], "down bubbled out of row1 into row2's first leaf")
    frame(ctx, input: InputState(commands: [.up]), draw: drawTwoRows)
    #expect(ctx.selection == [0, 0, 1], "up bubbled back into row1's edge leaf in document order")
    frame(ctx, input: InputState(commands: [.down]), draw: drawTwoRows)
    #expect(ctx.selection == [0, 1, 0], "down from b also lands on row2's first leaf")
  }

  @Test func directionFromTheRootStops() {
    let ctx = Interaction()
    frame(ctx)
    select(ctx, [.out, .out])
    #expect(ctx.selection == [])
    select(ctx, [.down, .up, .left, .right])
    #expect(ctx.selection == [])
  }

  @Test func leafCyclingWalksDocumentOrder() {
    let ctx = Interaction()
    frame(ctx)
    #expect(ctx.selection == [0, 0])
    select(ctx, [.nextLeaf])
    #expect(ctx.selection == [0, 1])
    select(ctx, [.nextLeaf])
    #expect(ctx.selection == [0, 2, 0], "cycling descends into groups")
    select(ctx, [.nextLeaf])
    #expect(ctx.selection == [0, 2, 1])
    select(ctx, [.nextLeaf])
    #expect(ctx.selection == [0, 0], "wrapped past the last leaf")
    select(ctx, [.previousLeaf])
    #expect(ctx.selection == [0, 2, 1], "wrapped back to the last leaf")
  }

  @Test func leafCyclingFromAGroup() {
    let ctx = Interaction()
    select(ctx, [.down, .down])
    #expect(ctx.selection == [0, 2], "cursor on the row group")
    select(ctx, [.nextLeaf])
    #expect(ctx.selection == [0, 2, 0])
    select(ctx, [.out])
    select(ctx, [.previousLeaf])
    #expect(ctx.selection == [0, 1])
  }


  @Test func activateClicksSelectedLeaf() {
    let ctx = Interaction()
    select(ctx, [.down])
    let states = frame(ctx, input: InputState(commands: [.activate]))
    #expect(states[WidgetID("b")]?.clicked == true)
    #expect(states[WidgetID("b")]?.hovered == true)
    #expect(states[WidgetID("a")]?.clicked == false)
    #expect(states[WidgetID("a")]?.hovered == false, "exactly one widget carries the cursor")
  }

  @Test func activateOnAGroupDoesNotClick() {
    let ctx = Interaction()
    select(ctx, [.down, .down])
    let states = frame(ctx, input: InputState(commands: [.activate]))
    #expect(states.values.allSatisfy { !$0.clicked })
  }


  @Test func hoverMovesCursorViaMacro() {
    let ctx = Interaction()
    frame(ctx)
    frame(ctx, input: InputState(pointerPosition: Point(x: 75, y: 50)))
    #expect(ctx.selection == [0, 2, 1])
    #expect(ctx.lastMacro == [.out, .in, .down, .down, .in, .right])
  }

  @Test func parkedPointerDoesNotFightKeyboard() {
    let ctx = Interaction()
    frame(ctx)
    frame(ctx, input: InputState(pointerPosition: Point(x: 75, y: 50)))
    #expect(ctx.selection == [0, 2, 1])
    frame(
      ctx,
      input: InputState(pointerPosition: Point(x: 75, y: 50), commands: [.out, .out]))
    #expect(ctx.selection == [0], "the still pointer did not re-assert its hover")
  }

  @Test func clickIsMacroThenActivate() {
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
      ctx.beginGroup(.none, rect: Rect(x: 0, y: 0, width: 100, height: 100))
      states[WidgetID("back")] = ctx.interactiveBehavior(
        id: WidgetID("back"), rect: Rect(x: 0, y: 0, width: 100, height: 100))
      states[WidgetID("front")] = ctx.interactiveBehavior(
        id: WidgetID("front"), rect: Rect(x: 0, y: 0, width: 100, height: 100))
      ctx.endGroup()
    }
    frame(ctx, input: InputState(pointerPosition: Point(x: 50, y: 50)))
    #expect(ctx.selection == [0, 1], "front is the last-drawn child")
  }


  @Test func emptyGroupsArePruned() {
    let ctx = Interaction()
    frame(ctx) { ctx, states in
      ctx.beginGroup(.vertical, rect: Rect(x: 0, y: 0, width: 100, height: 100))
      ctx.beginGroup(.vertical, rect: Rect(x: 0, y: 0, width: 100, height: 50))
      ctx.beginGroup(.horizontal, rect: Rect(x: 0, y: 0, width: 50, height: 50))
      ctx.endGroup()
      ctx.endGroup()
      states[WidgetID("a")] = ctx.interactiveBehavior(
        id: WidgetID("a"), rect: Rect(x: 0, y: 50, width: 100, height: 50))
      ctx.endGroup()
    }
    #expect(ctx.selection == [0, 0], "the pruned groups occupy no path slots")
  }

  @Test func cursorFollowsWidgetIDAcrossRelayout() {
    let ctx = Interaction()
    select(ctx, [.down])
    #expect(ctx.selection == [0, 1])
    frame(ctx) { ctx, states in
      ctx.beginGroup(.vertical, rect: Rect(x: 0, y: 0, width: 100, height: 80))
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

  @Test func cursorClampsWhenLeafDisappears() {
    let ctx = Interaction()
    select(ctx, [.down, .down, .in, .right])
    #expect(ctx.selection == [0, 2, 1])
    frame(ctx) { ctx, states in
      ctx.beginGroup(.vertical, rect: Rect(x: 0, y: 0, width: 100, height: 40))
      states[WidgetID("a")] = ctx.interactiveBehavior(
        id: WidgetID("a"), rect: Rect(x: 0, y: 0, width: 100, height: 20))
      states[WidgetID("b")] = ctx.interactiveBehavior(
        id: WidgetID("b"), rect: Rect(x: 0, y: 20, width: 100, height: 20))
      ctx.endGroup()
    }
    #expect(ctx.selection == [0, 1], "clamped to the last valid sibling")
  }


  @Test func scrollMovesTheCursor() {
    let ctx = Interaction()
    select(ctx, [.down, .down])
    #expect(ctx.selection == [0, 2])
    frame(ctx, input: InputState(scrollDelta: Point(x: 0, y: 1)))
    #expect(ctx.selection == [0, 1])
    frame(ctx, input: InputState(scrollDelta: Point(x: 0, y: -3)))
    #expect(ctx.selection == [0, 2])
  }
}
