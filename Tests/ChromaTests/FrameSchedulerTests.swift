import Testing

@testable import Chroma

@MainActor
struct FrameSchedulerTests {
  final class Clock { var now = 100.0 }

  @Test func idleDoesNotProduceFramesAndMomentumUsesMinimumRate() throws {
    let clock = Clock()
    let scheduler = FrameScheduler(clock: { clock.now })
    scheduler.setRefreshRates(minimum: 30, maximum: 60)
    #expect(scheduler.nextFrame == nil)
    #expect(!scheduler.takeFrame())
    scheduler.requestContent()
    #expect(scheduler.takeFrame())
    #expect(scheduler.nextFrame == nil)
    scheduler.scrollMomentumActive = true
    let next = try #require(scheduler.nextFrame)
    #expect(next.deadline == 100 + 1.0 / 30)
    #expect(next.priority == .utility)
    clock.now = 100 + 1.0 / 60
    #expect(!scheduler.takeFrame())
    clock.now = next.deadline
    #expect(scheduler.takeFrame())
    #expect(scheduler.nextFrame?.deadline == clock.now + 1.0 / 30)
    scheduler.scrollMomentumActive = false
    #expect(scheduler.nextFrame == nil)
  }

  @Test func contentDemandCoalescesAndSupersedesMomentumWithinGlobalCap() throws {
    let clock = Clock()
    let scheduler = FrameScheduler(clock: { clock.now })
    scheduler.requestContent()
    #expect(scheduler.takeFrame())
    scheduler.scrollMomentumActive = true
    clock.now += 0.001
    for _ in 0..<100 { scheduler.requestContent() }
    let next = try #require(scheduler.nextFrame)
    #expect(next.priority == .userInitiated)
    #expect(next.deadline == 100 + 1.0 / 60)
    #expect(!scheduler.takeFrame())
    clock.now = next.deadline
    #expect(scheduler.takeFrame())
    #expect(scheduler.nextFrame != nil)
    #expect(scheduler.nextFrame?.deadline == clock.now + 1.0 / 30)
    #expect(!scheduler.takeFrame())
    clock.now = try #require(scheduler.nextFrame).deadline
    #expect(scheduler.takeFrame())
    scheduler.requestContent()
    #expect(scheduler.nextFrame?.deadline == clock.now + 1.0 / 60)
    #expect(!scheduler.takeFrame())
  }

  @Test func slowFramesAndLateWakeupsDoNotCatchUpWithBursts() throws {
    let clock = Clock()
    let scheduler = FrameScheduler(clock: { clock.now })
    scheduler.requestContent()
    #expect(scheduler.takeFrame())
    scheduler.scrollMomentumActive = true
    clock.now += 2
    #expect(scheduler.takeFrame())
    #expect(!scheduler.takeFrame())
    clock.now += 0.1
    scheduler.recordProducedFrame()
    scheduler.requestContent()
    #expect(scheduler.nextFrame?.deadline == clock.now + 1.0 / 60)
    scheduler.reset()
    #expect(scheduler.nextFrame == nil)
    #expect(scheduler.lastFrameTime == nil)
  }

  @Test func rateChangesAndScrollMomentumRemainCapped() throws {
    let clock = Clock()
    let scheduler = FrameScheduler(clock: { clock.now })
    scheduler.requestContent()
    #expect(scheduler.takeFrame())
    scheduler.scrollMomentumActive = true
    scheduler.setRefreshRates(minimum: 20, maximum: 40)
    #expect(scheduler.nextFrame?.deadline == 100 + 1.0 / 20)
    #expect(scheduler.nextFrame != nil)
    #expect(scheduler.nextFrame?.priority == .utility)
    scheduler.requestContent()
    #expect(scheduler.nextFrame?.deadline == 100 + 1.0 / 40)
    #expect(scheduler.nextFrame?.priority == .userInitiated)
    scheduler.setRefreshRates(minimum: 40, maximum: 40)
    clock.now = try #require(scheduler.nextFrame).deadline
    #expect(scheduler.takeFrame())
    #expect(scheduler.nextFrame?.deadline == clock.now + 1.0 / 40)
  }

  @Test func scheduledTasksUseSeparatePrioritiesAndOneGlobalCap() async {
    let scheduler = FrameScheduler()
    let clock = ContinuousClock()
    let frames = await withCheckedContinuation { continuation in
      var frames: [(TaskPriority, ContinuousClock.Instant)] = []
      scheduler.onFrame = {
        frames.append((Task.currentPriority, clock.now))
        switch frames.count {
        case 1: scheduler.scrollMomentumActive = true
        case 2: scheduler.requestContent()
        default:
          scheduler.isReady = false
          continuation.resume(returning: frames)
        }
      }
      scheduler.isReady = true
      scheduler.requestContent()
    }
    #expect(frames.count == 3)
    #expect(frames.map { $0.0 } == [.userInitiated, .utility, .userInitiated])
    #expect(frames[0].1.duration(to: frames[1].1) >= .seconds(1.0 / 30))
    #expect(frames[1].1.duration(to: frames[2].1) >= .seconds(1.0 / 60))
    scheduler.reset()
  }

  @Test func readinessAndResetCancelScheduledWork() async {
    let scheduler = FrameScheduler()
    var frames = 0
    scheduler.onFrame = { frames += 1 }
    scheduler.isReady = true
    scheduler.requestContent()
    scheduler.isReady = false
    await Task.yield()
    #expect(frames == 0)
    scheduler.isReady = true
    scheduler.reset()
    await Task.yield()
    #expect(frames == 0)
    #expect(scheduler.nextFrame == nil)
  }
}
