import Testing
@testable import Chroma

/// Tests for tree navigation: the one-cursor model, the six movement
/// commands, pointer-to-macro compilation, and click/activate semantics.
///
/// Tests drive `Interaction` the way the backend and blocks do:
/// `beginFrame` (carrying input), a simulated draw that registers groups and
/// leaves, then `endFrame`. Commands apply against the previous frame's
/// tree, so the first frame always just builds the tree.
@MainActor
struct NavigationTests {

  // MARK: Fixtures

  /// The standard fixture tree, mirroring what a block tree of nested stacks
  /// would register during draw:
  ///
  /// ```
  /// root (vertical)          0,0   100x60
  /// ├─ a (leaf)              0,0   100x20
  /// ├─ b (leaf)              0,20  100x20
  /// └─ row (horizontal)      0,40  100x20
  ///    ├─ c (leaf)           0,40   50x20
  ///    └─ d (leaf)          50,40   50x20
  /// ```
  ///
  /// Paths include the enclosing group: a = [0,0], b = [0,1], row = [0,2],
  /// c = [0,2,0], d = [0,2,1].
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

  /// Runs one full frame against the fixture tree, returning each leaf's
  /// state as observed during the draw.
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

  /// Builds the tree, then sends one command per frame (commands always run
  /// against the previous frame's tree).
  private func select(_ ctx: Interaction, _ commands: [UICommand]) {
    frame(ctx)
    for command in commands {
      frame(ctx, input: InputState(commands: [command]))
    }
  }

  // MARK: Movement

  /// With nothing selected, the cursor starts on the first leaf.
  @Test func firstFrameSelectsFirstLeaf() {
    let ctx = Interaction()
    frame(ctx)
    #expect(ctx.selection == [0, 0])
  }

  /// `down` walks siblings in a vertical group and clamps at the end;
  /// `up` walks back.
  @Test func verticalMovementWalksAndClamps() {
    let ctx = Interaction()
    select(ctx, [.down])
    #expect(ctx.selection == [0, 1])
    select(ctx, [.down])
    #expect(ctx.selection == [0, 2], "the horizontal row group is a sibling")
    select(ctx, [.down])
    #expect(ctx.selection == [0, 2], "clamped at the last sibling")
    select(ctx, [.up, .up])
    #expect(ctx.selection == [0, 0])
  }

  /// `in` steps into a group onto its first child; `out` climbs back to the
  /// parent, bottoming out at the root.
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

  /// `right`/`left` move inside a horizontal group and clamp; vertical
  /// commands are strict no-ops there (skips are a layer on top).
  @Test func horizontalMovementRespectsAxis() {
    let ctx = Interaction()
    select(ctx, [.down, .down, .in, .right])
    #expect(ctx.selection == [0, 2, 1])
    select(ctx, [.right])
    #expect(ctx.selection == [0, 2, 1], "clamped at the last sibling")
    select(ctx, [.down])
    #expect(ctx.selection == [0, 2, 1], "down does not apply in a horizontal group")
    select(ctx, [.left])
    #expect(ctx.selection == [0, 2, 0])
  }

  // MARK: Activation

  /// An `activate` command fires the selected leaf during draw, and only
  /// that leaf reports the cursor (`hovered`).
  @Test func activateClicksSelectedLeaf() {
    let ctx = Interaction()
    select(ctx, [.down])  // cursor on b
    let states = frame(ctx, input: InputState(commands: [.activate]))
    #expect(states[WidgetID("b")]?.clicked == true)
    #expect(states[WidgetID("b")]?.hovered == true)
    #expect(states[WidgetID("a")]?.clicked == false)
    #expect(states[WidgetID("a")]?.hovered == false, "exactly one widget carries the cursor")
  }

  /// Activate with the cursor on a group does nothing to the leaves.
  @Test func activateOnAGroupDoesNotClick() {
    let ctx = Interaction()
    select(ctx, [.down, .down])  // cursor on the row group
    let states = frame(ctx, input: InputState(commands: [.activate]))
    #expect(states.values.allSatisfy { !$0.clicked })
  }

  // MARK: Pointer macros

  /// Hovering compiles into the move macro that walks the cursor from its
  /// current position to the hovered leaf: out to the common ancestor, then
  /// in + sibling moves back down.
  @Test func hoverMovesCursorViaMacro() {
    let ctx = Interaction()
    frame(ctx)  // cursor on a = [0,0]
    // Pointer enters d (at 75,50).
    frame(ctx, input: InputState(pointerPosition: Point(x: 75, y: 50)))
    #expect(ctx.selection == [0, 2, 1])
    #expect(ctx.lastMacro == [.out, .in, .down, .down, .in, .right])
  }

  /// A parked pointer generates no macros, so keyboard movement is never
  /// fought by the mouse sitting over another widget.
  @Test func parkedPointerDoesNotFightKeyboard() {
    let ctx = Interaction()
    frame(ctx)
    // Hover d, then use the keyboard without moving the mouse.
    frame(ctx, input: InputState(pointerPosition: Point(x: 75, y: 50)))
    #expect(ctx.selection == [0, 2, 1])
    frame(
      ctx,
      input: InputState(pointerPosition: Point(x: 75, y: 50), commands: [.out, .out]))
    #expect(ctx.selection == [0], "the still pointer did not re-assert its hover")
  }

  /// A full click — press then release on the same leaf — moves the cursor
  /// there, shows the press while held, and activates on release.
  @Test func clickIsMacroThenActivate() {
    let ctx = Interaction()
    frame(ctx)  // cursor on a
    // Press on c.
    var states = frame(
      ctx,
      input: InputState(
        pointerPosition: Point(x: 25, y: 50), pointerDown: true, pointerPressed: true))
    #expect(ctx.selection == [0, 2, 0], "press moved the cursor to c")
    #expect(states[WidgetID("c")]?.held == true)
    #expect(states[WidgetID("c")]?.clicked == false)
    // Release on c.
    states = frame(
      ctx,
      input: InputState(pointerPosition: Point(x: 25, y: 50), pointerReleased: true))
    #expect(states[WidgetID("c")]?.clicked == true)
    #expect(states[WidgetID("c")]?.held == false)
  }

  /// Press inside, release outside: no activation, matching the platform
  /// convention.
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

  /// When several leaves overlap, the top-most (last drawn) wins the
  /// pointer, just like paint order.
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

  // MARK: Tree stability

  /// Groups with no interactive descendants are pruned, so decoration and
  /// spacing stacks never intercept navigation.
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

  /// When the tree's shape changes, the cursor follows the selected leaf's
  /// WidgetID to its new position.
  @Test func cursorFollowsWidgetIDAcrossRelayout() {
    let ctx = Interaction()
    select(ctx, [.down])  // cursor on b = [0,1]
    #expect(ctx.selection == [0, 1])
    // A new leaf appears before b: b shifts to [0,2].
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

  /// When the selected leaf disappears, the cursor clamps somewhere sane
  /// rather than pointing into the void.
  @Test func cursorClampsWhenLeafDisappears() {
    let ctx = Interaction()
    select(ctx, [.down, .down, .in, .right])  // cursor on d = [0,2,1]
    #expect(ctx.selection == [0, 2, 1])
    // The whole row group vanishes, leaving only a and b.
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

  // MARK: Scroll

  /// The scroll wheel is another device speaking the language: one sibling
  /// step per frame.
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
