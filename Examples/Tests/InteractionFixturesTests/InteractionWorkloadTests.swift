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
}
