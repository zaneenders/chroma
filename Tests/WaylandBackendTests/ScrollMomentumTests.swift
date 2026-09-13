import Testing
@testable import WaylandBackend

struct ScrollMomentumTests {
  private func fling() -> ScrollMomentum {
    var momentum = ScrollMomentum()
    momentum.record(delta: -10, time: 100)
    momentum.record(delta: -10, time: 110)
    momentum.stop(time: 115, now: 1)
    return momentum
  }

  @Test func decaysAndStops() {
    var momentum = fling()
    #expect(momentum.isActive)
    let first = momentum.advance(now: 1.01)
    let second = momentum.advance(now: 1.02)
    #expect(first < second && second < 0)
    for frame in 3...150 { _ = momentum.advance(now: 1 + Double(frame) / 100) }
    #expect(!momentum.isActive)
  }

  @Test func flickCarriesFartherWithFasterRelease() {
    var momentum = fling()
    // A 1000-point/s gesture now releases at 1250 points/s.
    let first = momentum.advance(now: 1.01)
    #expect(first < -12 && first > -12.5)
    var distance = first
    for frame in 2...150 { distance += momentum.advance(now: 1 + Double(frame) / 100) }
    // Previously this gesture travelled about 124 points after release.
    #expect(distance < -207 && distance > -209)
    #expect(!momentum.isActive)
  }

  @Test func staleReleaseDoesNotFling() {
    var momentum = ScrollMomentum()
    momentum.record(delta: 10, time: 100)
    momentum.record(delta: 10, time: 110)
    momentum.stop(time: 250, now: 1)
    #expect(!momentum.isActive)
  }

  @Test func newGestureAndCancellationStopMomentum() {
    var momentum = fling()
    momentum.record(delta: 2, time: 200)
    #expect(!momentum.isActive)
    momentum.cancel()
    #expect(momentum.advance(now: 1.01) == 0)
  }

  @Test func longFrameGapDoesNotJump() {
    var momentum = fling()
    #expect(momentum.advance(now: 2) == 0)
    #expect(!momentum.isActive)
  }

  @Test func timestampWraparound() {
    var momentum = ScrollMomentum()
    momentum.record(delta: 10, time: UInt32.max - 4)
    momentum.record(delta: 10, time: 5)
    momentum.stop(time: 6, now: 1)
    #expect(momentum.advance(now: 1.01) > 0)
  }

  @Test func decayIsRefreshRateIndependent() {
    var fast = fling()
    var slow = fling()
    var fastDistance: Float = 0
    var slowDistance: Float = 0
    for frame in 1...12 { fastDistance += fast.advance(now: 1 + Double(frame) / 120) }
    for frame in 1...6 { slowDistance += slow.advance(now: 1 + Double(frame) / 60) }
    #expect(abs(fastDistance - slowDistance) < 0.001)
  }

  @MainActor @Test func wheelDoesNotStartMomentum() {
    let input = InputAccumulator()
    input.scrollSource(isFinger: false)
    input.scrollBy(x: 0, y: -10, time: 100)
    input.scrollBy(x: 0, y: -10, time: 110)
    input.stopScroll(horizontal: false, time: 115)
    #expect(!input.hasScrollMomentum)
    #expect(input.frameInput().scrollDelta.y == -20)
    #expect(input.frameInput().scrollDelta.y == 0)
  }
}
