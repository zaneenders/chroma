import Chroma
import ChromaTesting
import InteractionFixtures
import Testing

@MainActor
struct InteractionWorkloadTests {
  @Test func pointerEventsReuseRegistrationsBeforeOneScheduledRender() {
    let counters = InteractionWorkloadCounters()
    let host = HeadlessHost(size: Size(width: 400, height: 600))
    host.content = InteractionWorkload(count: 100, lazy: false, counters: counters)
    host.renderScheduled()
    counters.resetDraws()
    host.handleInput(InputState(pointerPosition: Point(x: 40, y: 40)))
    let firstEventDraws = counters.rowDraws
    #expect(firstEventDraws == 0)
    host.handleInput(InputState(pointerPosition: Point(x: 41, y: 41)))
    #expect(counters.rowDraws == firstEventDraws * 2)
    counters.resetDraws()
    host.renderScheduled()
    #expect(counters.rowDraws > 0)
    #expect(counters.activations == 0)
  }

  @Test func clickEdgesAreAppliedOnceBeforeRendering() {
    let counters = InteractionWorkloadCounters()
    let host = HeadlessHost(size: Size(width: 400, height: 600))
    host.content = InteractionWorkload(count: 100, lazy: false, counters: counters)
    host.renderScheduled()
    let point = Point(x: 40, y: 40)
    host.handleInput(
      InputState(
        pointerPosition: point, pointerPressPosition: point, pointerDown: true, pointerPressed: true))
    host.handleInput(InputState(pointerPosition: point, pointerReleased: true))
    #expect(counters.activations == 1)
    host.renderScheduled()
    #expect(counters.activations == 1)
  }

  @Test func replacingContentBeforeInputUsesNewCallbacks() {
    let old = InteractionWorkloadCounters()
    let current = InteractionWorkloadCounters()
    let host = HeadlessHost(size: Size(width: 400, height: 600))
    host.content = InteractionWorkload(count: 100, lazy: false, counters: old)
    host.renderScheduled()
    host.content = InteractionWorkload(count: 100, lazy: false, counters: current)
    let point = Point(x: 40, y: 40)
    host.handleInput(
      InputState(
        pointerPosition: point, pointerPressPosition: point, pointerDown: true, pointerPressed: true))
    host.handleInput(InputState(pointerPosition: point, pointerReleased: true))
    host.renderScheduled()
    #expect(old.activations == 0)
    #expect(current.activations == 1)
  }

  @Test func lazyRowsBoundDrawWorkToTheViewport() {
    let counters = InteractionWorkloadCounters()
    let host = HeadlessHost(size: Size(width: 400, height: 600))
    host.content = InteractionWorkload(count: 5_000, lazy: true, counters: counters)
    host.renderScheduled()
    counters.resetDraws()
    host.handleInput(InputState(pointerPosition: Point(x: 40, y: 40)))
    #expect(counters.rowDraws == 0)
    host.renderScheduled()
    #expect(counters.rowDraws > 0)
    #expect(counters.rowDraws < 100)
  }
  @Test(arguments: [false, true])
  func scrollBatchesPreserveOffsetsAndClickUsesScrolledRows(lazy: Bool) {
    let counters = InteractionWorkloadCounters()
    let controller = ScrollViewController()
    let host = HeadlessHost(size: Size(width: 400, height: 600))
    host.content = InteractionWorkload(count: 100, lazy: lazy, counters: counters, controller: controller)
    host.renderScheduled()
    let point = Point(x: 40, y: 40)
    counters.resetDraws()
    for _ in 0..<8 {
      host.handleInput(InputState(pointerPosition: point, scrollDelta: Point(x: 0, y: -28)))
    }
    #expect(counters.rowDraws == 0)
    host.handleInput(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
    host.handleInput(InputState(pointerPosition: point, pointerReleased: true))
    #expect(counters.lastActivatedRow == 9)
    #expect(counters.activations == 1)
    host.renderScheduled()
    #expect(controller.offset == 224)
    #expect(counters.activations == 1)
  }

  @Test(arguments: [false, true])
  func reversingScrollAtBoundaryIsNotEquivalentToSummingDeltas(lazy: Bool) {
    let counters = InteractionWorkloadCounters()
    let controller = ScrollViewController()
    let host = HeadlessHost(size: Size(width: 400, height: 600))
    host.content = InteractionWorkload(count: 100, lazy: lazy, counters: counters, controller: controller)
    host.renderScheduled()
    let point = Point(x: 40, y: 40)
    host.handleInput(InputState(pointerPosition: point, scrollDelta: Point(x: 0, y: 28)))
    host.handleInput(InputState(pointerPosition: point, scrollDelta: Point(x: 0, y: -28)))
    host.renderScheduled()
    #expect(controller.offset == 28)
  }

  @Test func draggingAcrossRowsDoesNotActivateEitherRow() {
    let counters = InteractionWorkloadCounters()
    let host = HeadlessHost(size: Size(width: 400, height: 600))
    host.content = InteractionWorkload(count: 100, lazy: false, counters: counters)
    host.renderScheduled()
    let origin = Point(x: 40, y: 40)
    host.handleInput(InputState(pointerPosition: origin, pointerDown: true, pointerPressed: true))
    counters.resetDraws()
    for row in 2..<10 {
      host.handleInput(
        InputState(
          pointerPosition: Point(x: 40, y: Float(row) * 28 + 12),
          pointerPressPosition: origin, pointerDown: true))
    }
    #expect(counters.rowDraws == 0)
    host.handleInput(InputState(pointerPosition: Point(x: 40, y: 264), pointerReleased: true))
    host.renderScheduled()
    #expect(counters.activations == 0)
  }

  @Test func movingBetweenScrollViewsDoesNotCombineTheirDeltas() {
    let left = ScrollViewController()
    let right = ScrollViewController()
    let host = HeadlessHost(size: Size(width: 800, height: 600))
    host.content = HStack(spacing: 0) {
      InteractionWorkload(count: 100, lazy: true, counters: InteractionWorkloadCounters(), controller: left)
        .sizing(x: .fixed(400))
      InteractionWorkload(count: 100, lazy: true, counters: InteractionWorkloadCounters(), controller: right)
        .sizing(x: .fixed(400))
    }
    host.renderScheduled()
    host.handleInput(InputState(pointerPosition: Point(x: 40, y: 40), scrollDelta: Point(x: 0, y: -28)))
    host.handleInput(InputState(pointerPosition: Point(x: 440, y: 40), scrollDelta: Point(x: 0, y: -56)))
    host.renderScheduled()
    #expect(left.offset == 28)
    #expect(right.offset == 56)
  }

  @Test func parentScrollingChangesTheNestedScrollHitRegionBeforeTheNextEvent() {
    let parent = ScrollViewController()
    let child = ScrollViewController()
    let host = HeadlessHost(size: Size(width: 400, height: 600))
    host.content = ScrollView(controller: parent) {
      VStack(spacing: 0) {
        Color.white.sizing(y: .fixed(100))
        InteractionWorkload(count: 100, lazy: true, counters: InteractionWorkloadCounters(), controller: child)
          .sizing(y: .fixed(100))
        Color.white.sizing(y: .fixed(1_000))
      }
    }
    host.renderScheduled()
    let point = Point(x: 40, y: 50)
    host.handleInput(InputState(pointerPosition: point, scrollDelta: Point(x: 0, y: -100)))
    host.handleInput(InputState(pointerPosition: point, scrollDelta: Point(x: 0, y: -28)))
    host.renderScheduled()
    #expect(parent.offset == 128)
    #expect(child.offset == 28)
  }

}
