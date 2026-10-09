import Testing

@testable import Chroma
@testable import WaylandBackend

/// Keeps momentum recovery separate from the dispatch model: these are the real
/// momentum and scheduler state machines driven by a shared virtual clock.
@MainActor
struct InputBacklogMomentumTests {
  final class Clock { var now = 100.0 }

  @Test(arguments: [false, true])
  func finiteBacklogReleaseDecaysAtTheMinimumRateThenGoesIdle(diagonal: Bool) throws {
    let clock = Clock()
    let scheduler = FrameScheduler(clock: { clock.now })
    defer { scheduler.reset() }
    scheduler.setRefreshRates(minimum: 30, maximum: 60)
    scheduler.requestContent()
    #expect(scheduler.takeFrame())
    var vertical = ScrollMomentum()
    var horizontal = ScrollMomentum()
    for index in 0..<180 {
      let time = UInt32(index * 1_000 / 60)
      vertical.record(delta: -1, time: time)
      if diagonal { horizontal.record(delta: -1, time: time) }
      clock.now += diagonal ? 0.046 : 0.023
      scheduler.requestContent()
    }
    // The release timestamp remains close to the final protocol sample even
    // though the simulated main-actor work has exceeded the source duration.
    vertical.stop(time: 3_000, now: clock.now)
    if diagonal { horizontal.stop(time: 3_000, now: clock.now) }
    scheduler.scrollMomentumActive = vertical.isActive || horizontal.isActive
    #expect(scheduler.scrollMomentumActive)
    #expect(scheduler.takeFrame())
    var frames = 0
    var distance = Point.zero
    for _ in 0..<200 {
      guard let next = scheduler.nextFrame else { break }
      let previousStart = try #require(scheduler.lastFrameTime)
      #expect(next.deadline == previousStart + 1.0 / 30)
      #expect(!scheduler.takeFrame())
      clock.now = next.deadline
      #expect(scheduler.takeFrame())
      distance.y += vertical.advance(now: clock.now)
      distance.x += horizontal.advance(now: clock.now)
      scheduler.scrollMomentumActive = vertical.isActive || horizontal.isActive
      frames += 1
    }
    #expect(frames > 0 && frames < 200)
    #expect(distance.y < 0)
    #expect(diagonal ? distance.x == distance.y : distance.x == 0)
    #expect(!scheduler.scrollMomentumActive)
    #expect(scheduler.nextFrame == nil)
    clock.now += 10
    #expect(!scheduler.takeFrame())
  }
}
