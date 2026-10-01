import Chroma
import Testing

@testable import WaylandBackend

@MainActor
struct InputAccumulatorTests {
  @Test func deliveredPointerEdgesMotionAndScrollRemainOrdered() {
    let input = InputAccumulator()
    input.pointerEntered(x: 1, y: 2)
    input.pointerMoved(x: 3, y: 4)
    input.pointerPressed()
    input.scrollBy(x: 1, y: 2, time: 0)
    input.pointerMoved(x: 5, y: 6)
    input.scrollBy(x: -1, y: -2, time: 1)
    input.pointerReleased()
    input.pointerLeft()
    let events = input.drain()
    #expect(events.count == 8)
    #expect(
      events.map(\.pointerPosition) == [
        Point(x: 1, y: 2), Point(x: 3, y: 4),
        Point(x: 3, y: 4), Point(x: 3, y: 4), Point(x: 5, y: 6), Point(x: 5, y: 6),
        Point(x: 5, y: 6), Point(x: -1, y: -1),
      ])
    #expect(events[2].pointerPressed)
    #expect(events[3].scrollDelta == Point(x: 1, y: 2))
    #expect(events[5].scrollDelta == Point(x: -1, y: -2))
    #expect(events[6].pointerReleased)
    #expect(input.drain().isEmpty)
  }
}
