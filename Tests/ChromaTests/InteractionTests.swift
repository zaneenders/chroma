import Testing
@testable import Chroma

/// Tests for the per-frame interaction context, especially the pointer-capture
/// lifecycle through `buttonBehavior` and `beginFrame`/`endFrame`.
@MainActor
struct InteractionTests {

  /// A normal press-and-release inside the widget clicks.
  @Test func clickInside() {
    let ctx = Interaction()
    // frame 1: press
    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),
      pointerDown: true,
      pointerPressed: true
    ))
    let state1 = ctx.buttonBehavior(id: WidgetID("btn"), rect: Rect(x: 0, y: 0, width: 100, height: 100))
    #expect(state1.hovered)
    #expect(state1.held)
    #expect(!state1.clicked)
    #expect(ctx.active == WidgetID("btn"))
    ctx.endFrame()

    // frame 2: release
    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),
      pointerDown: false,
      pointerReleased: true
    ))
    let state2 = ctx.buttonBehavior(id: WidgetID("btn"), rect: Rect(x: 0, y: 0, width: 100, height: 100))
    #expect(state2.hovered)
    #expect(!state2.held)
    #expect(state2.clicked)
    #expect(ctx.active == nil)
    ctx.endFrame()
  }

  /// Releasing outside the active widget does NOT click.
  @Test func releaseOutsideDoesNotClick() {
    let ctx = Interaction()
    // frame 1: press inside
    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),
      pointerDown: true,
      pointerPressed: true
    ))
    _ = ctx.buttonBehavior(id: WidgetID("btn"), rect: Rect(x: 0, y: 0, width: 100, height: 100))
    #expect(ctx.active == WidgetID("btn"))
    ctx.endFrame()

    // frame 2: release outside
    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 200, y: 200),
      pointerDown: false,
      pointerReleased: true
    ))
    let state2 = ctx.buttonBehavior(id: WidgetID("btn"), rect: Rect(x: 0, y: 0, width: 100, height: 100))
    #expect(!state2.hovered)
    #expect(!state2.clicked)
    #expect(ctx.active == nil)   // capture cleared
    ctx.endFrame()
  }

  /// When the active widget disappears before the release frame, `endFrame`
  /// clears the stale active so other widgets can be interacted with again.
  @Test func disappearingWidgetClearsActive() {
    let ctx = Interaction()
    let idA = WidgetID("A")
    let idB = WidgetID("B")
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)

    // frame 1: press inside widget A — it captures active
    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),
      pointerDown: true,
      pointerPressed: true
    ))
    _ = ctx.buttonBehavior(id: idA, rect: rect)
    #expect(ctx.active == idA)
    ctx.endFrame()

    // frame 2: pointer is still down, but widget A is gone (not drawn).
    // No widget calls buttonBehavior for "A".
    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),
      pointerDown: true,
      pointerPressed: false,
      pointerReleased: false
    ))
    // Widget B is drawn — it should NOT be hovered because active is still "A"
    let stateB = ctx.buttonBehavior(id: idB, rect: rect)
    #expect(!stateB.hovered, "B should not be hovered while A has capture")
    #expect(ctx.active == idA)
    ctx.endFrame()

    // frame 3: pointer is released. Widget A is still gone. endFrame must clear.
    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),
      pointerDown: false,
      pointerReleased: true
    ))
    // Widget B is drawn again — still not hovered this frame because active
    // hasn't been cleared yet (buttonBehavior for B runs before we'd know
    // A is gone). But endFrame will clear it after draw.
    let stateB3 = ctx.buttonBehavior(id: idB, rect: rect)
    // B is still blocked this frame (capture persists through draw)
    #expect(!stateB3.hovered)
    ctx.endFrame()
    #expect(ctx.active == nil, "endFrame should clear stale active on release")

    // frame 4: now B should be fully interactive again
    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),
      pointerDown: false,
      pointerPressed: false,
      pointerReleased: false
    ))
    let stateB4 = ctx.buttonBehavior(id: idB, rect: rect)
    #expect(stateB4.hovered, "B should be hoverable after stale active cleared")
    ctx.endFrame()
  }

  /// When the active widget IS still present and gets released, `endFrame`
  /// is a safe no-op (widget already cleared active).
  @Test func endFrameNoopWhenWidgetAlreadyCleared() {
    let ctx = Interaction()
    let id = WidgetID("btn")
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)

    // press
    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),
      pointerDown: true,
      pointerPressed: true
    ))
    _ = ctx.buttonBehavior(id: id, rect: rect)
    #expect(ctx.active == id)
    ctx.endFrame()

    // release inside — widget clears active, then endFrame sees pointerReleased
    // and would clear again, but it's already nil.
    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),
      pointerDown: false,
      pointerReleased: true
    ))
    let state = ctx.buttonBehavior(id: id, rect: rect)
    #expect(state.clicked)
    #expect(ctx.active == nil)   // widget cleared it
    ctx.endFrame()
    #expect(ctx.active == nil)   // endFrame didn't break anything
  }

  /// Only the capturing widget can become hot while the button is held.
  @Test func captureBlocksOtherWidgets() {
    let ctx = Interaction()
    let idA = WidgetID("A")
    let idB = WidgetID("B")
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)

    // press on A
    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),
      pointerDown: true,
      pointerPressed: true
    ))
    _ = ctx.buttonBehavior(id: idA, rect: rect)
    #expect(ctx.active == idA)
    ctx.endFrame()

    // while held, B at same position is not hovered
    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),
      pointerDown: true
    ))
    let stateB = ctx.buttonBehavior(id: idB, rect: rect)
    #expect(!stateB.hovered)
    #expect(ctx.hot == nil)   // B didn't claim hot
    ctx.endFrame()
  }

  /// `beginFrame` clears `hot` each frame so stale hover doesn't persist.
  @Test func beginFrameClearsHot() {
    let ctx = Interaction()
    let idA = WidgetID("A")
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)

    ctx.beginFrame(input: InputState(pointerPosition: Point(x: 50, y: 50)))
    _ = ctx.buttonBehavior(id: idA, rect: rect)
    #expect(ctx.hot == idA)
    ctx.endFrame()

    // next frame, pointer outside — hot must be nil after beginFrame
    ctx.beginFrame(input: InputState(pointerPosition: Point(x: -1, y: -1)))
    #expect(ctx.hot == nil)
    // draw A again but it shouldn't claim hot (pointer outside)
    _ = ctx.buttonBehavior(id: idA, rect: rect)
    #expect(ctx.hot == nil)
    ctx.endFrame()
  }

  /// endFrame does NOT clear active when pointer is still down (only on release).
  @Test func endFramePreservesActiveWhileHeld() {
    let ctx = Interaction()
    let id = WidgetID("btn")
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)

    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),
      pointerDown: true,
      pointerPressed: true
    ))
    _ = ctx.buttonBehavior(id: id, rect: rect)
    #expect(ctx.active == id)
    ctx.endFrame()
    #expect(ctx.active == id, "active persists while button held")

    // next frame: still held, no press/release edge
    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),
      pointerDown: true
    ))
    _ = ctx.buttonBehavior(id: id, rect: rect)
    #expect(ctx.active == id)
    ctx.endFrame()
    #expect(ctx.active == id, "active persists while button held")
  }

  /// A press that starts outside the widget, drags inside, and releases
  /// inside — all within a single frame — must NOT fire a click. The
  /// capture decision uses the press position, not the final position.
  @Test func pressOutsideDragInsideReleaseInsideSameFrameDoesNotClick() {
    let ctx = Interaction()
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)

    // Press outside (200, 200), drag to (50, 50), release — all in one frame.
    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),        // final position: inside
      pointerPressPosition: Point(x: 200, y: 200),  // press position: outside
      pointerDown: false,
      pointerPressed: true,
      pointerReleased: true
    ))
    let state = ctx.buttonBehavior(id: WidgetID("btn"), rect: rect)
    #expect(!state.clicked, "press outside must not click even when released inside")
    #expect(ctx.active == nil, "no capture because press was outside")
    ctx.endFrame()
  }

  // MARK: - Overlapping widgets (ZStack hit-testing)

  /// When two widgets overlap and neither is active, only the top-most
  /// (last-drawn) widget should report `hovered == true` once the
  /// resolved hot settles (second frame onward).
  @Test func overlappingOnlyTopMostHovered() {
    let ctx = Interaction()
    let back = WidgetID("back")
    let front = WidgetID("front")
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)

    // Frame 1: pointer enters overlap — both may report hovered
    // (resolvedHot is nil on the first frame).
    ctx.beginFrame(input: InputState(pointerPosition: Point(x: 50, y: 50)))
    let b1 = ctx.buttonBehavior(id: back, rect: rect)
    let f1 = ctx.buttonBehavior(id: front, rect: rect)
    // First frame: both hit the resolvedHot==nil path.
    #expect(b1.hovered)
    #expect(f1.hovered)
    ctx.endFrame()

    // Frame 2: resolvedHot is now `front` (last writer wins).
    ctx.beginFrame(input: InputState(pointerPosition: Point(x: 50, y: 50)))
    let b2 = ctx.buttonBehavior(id: back, rect: rect)
    let f2 = ctx.buttonBehavior(id: front, rect: rect)
    #expect(!b2.hovered, "back widget must not be hovered when front is on top")
    #expect(f2.hovered, "front widget must be hovered")
    ctx.endFrame()
  }

  /// When two overlapping widgets receive a press, the top-most widget
  /// (identified by resolvedHot) must capture the press, not the
  /// back-most widget that happens to be drawn first.
  @Test func overlappingPressCapturesTopMost() {
    let ctx = Interaction()
    let back = WidgetID("back")
    let front = WidgetID("front")
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)

    // Settle hover so resolvedHot = front.
    ctx.beginFrame(input: InputState(pointerPosition: Point(x: 50, y: 50)))
    _ = ctx.buttonBehavior(id: back, rect: rect)
    _ = ctx.buttonBehavior(id: front, rect: rect)
    ctx.endFrame()

    // Press.
    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),
      pointerDown: true,
      pointerPressed: true
    ))
    let bState = ctx.buttonBehavior(id: back, rect: rect)
    let fState = ctx.buttonBehavior(id: front, rect: rect)
    #expect(!bState.held, "back widget must not capture press")
    #expect(!bState.hovered, "back widget must not show hover during press")
    #expect(fState.held, "front widget must capture press")
    #expect(ctx.active == front, "active must be the front widget")
    ctx.endFrame()
  }

  /// When the active (front) widget is released inside, it clicks.
  /// The back widget must not click.
  @Test func overlappingReleaseTopMostClicks() {
    let ctx = Interaction()
    let back = WidgetID("back")
    let front = WidgetID("front")
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)

    // Settle hover and press.
    ctx.beginFrame(input: InputState(pointerPosition: Point(x: 50, y: 50)))
    _ = ctx.buttonBehavior(id: back, rect: rect)
    _ = ctx.buttonBehavior(id: front, rect: rect)
    ctx.endFrame()

    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),
      pointerDown: true,
      pointerPressed: true
    ))
    _ = ctx.buttonBehavior(id: back, rect: rect)
    _ = ctx.buttonBehavior(id: front, rect: rect)
    ctx.endFrame()

    // Release.
    ctx.beginFrame(input: InputState(
      pointerPosition: Point(x: 50, y: 50),
      pointerDown: false,
      pointerReleased: true
    ))
    let bState = ctx.buttonBehavior(id: back, rect: rect)
    let fState = ctx.buttonBehavior(id: front, rect: rect)
    #expect(!bState.clicked, "back widget must not click")
    #expect(fState.clicked, "front widget must click")
    #expect(ctx.active == nil, "active must clear after click")
    ctx.endFrame()
  }

  /// When the pointer moves to a non-overlapping area of the back widget,
  /// the back widget becomes the top-most widget under the pointer and
  /// should gain hover after one frame of settling.
  @Test func overlappingPointerMovesToBackWidget() {
    let ctx = Interaction()
    let back = WidgetID("back")
    let front = WidgetID("front")
    let bigRect = Rect(x: 0, y: 0, width: 200, height: 100)
    let smallRect = Rect(x: 0, y: 0, width: 100, height: 100)

    // Settle with pointer in overlap area → front is hot.
    ctx.beginFrame(input: InputState(pointerPosition: Point(x: 50, y: 50)))
    _ = ctx.buttonBehavior(id: back, rect: bigRect)
    _ = ctx.buttonBehavior(id: front, rect: smallRect)
    ctx.endFrame()

    // Move pointer to back-only area (front doesn't contain this point).
    ctx.beginFrame(input: InputState(pointerPosition: Point(x: 150, y: 50)))
    let b1 = ctx.buttonBehavior(id: back, rect: bigRect)
    let f1 = ctx.buttonBehavior(id: front, rect: smallRect)
    // First frame after move: front was hot but pointer is not in front,
    // and back hasn't settled as hot yet.
    #expect(!b1.hovered, "back not hovered until resolvedHot settles")
    #expect(!f1.hovered)
    ctx.endFrame()

    // Next frame: back is now hot.
    ctx.beginFrame(input: InputState(pointerPosition: Point(x: 150, y: 50)))
    let b2 = ctx.buttonBehavior(id: back, rect: bigRect)
    let f2 = ctx.buttonBehavior(id: front, rect: smallRect)
    #expect(b2.hovered, "back must be hovered after settling")
    #expect(!f2.hovered)
    ctx.endFrame()
  }

  /// `hot` still reflects the current frame's claim (last writer wins)
  /// so callers can inspect which widget claimed hover during draw.
  @Test func overlappingHotReflectsCurrentFrameClaim() {
    let ctx = Interaction()
    let back = WidgetID("back")
    let front = WidgetID("front")
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)

    // Frame 1: both claim, front overwrites.
    ctx.beginFrame(input: InputState(pointerPosition: Point(x: 50, y: 50)))
    _ = ctx.buttonBehavior(id: back, rect: rect)
    #expect(ctx.hot == back, "hot is back (so far)")
    _ = ctx.buttonBehavior(id: front, rect: rect)
    #expect(ctx.hot == front, "hot is front (last writer)")
    ctx.endFrame()
  }
}
