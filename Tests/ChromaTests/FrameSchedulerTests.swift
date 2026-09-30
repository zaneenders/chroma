import Testing

@testable import Chroma

@MainActor
struct FrameSchedulerTests {
  final class Clock { var now = 100.0 }

  @Test func idleDoesNotProduceFramesAndAnimationsUseMinimumRate() throws {
    let clock = Clock()
    let scheduler = FrameScheduler(clock: { clock.now })
    scheduler.setRefreshRates(minimum: 30, maximum: 60)
    #expect(scheduler.nextFrame == nil)
    #expect(scheduler.takeFrame() == nil)
    scheduler.requestContent()
    #expect(scheduler.takeFrame() == .content)
    #expect(scheduler.nextFrame == nil)
    scheduler.animationsActive = true
    let next = try #require(scheduler.nextFrame)
    #expect(next.deadline == 100 + 1.0 / 30)
    #expect(next.kind == .animation)
    #expect(next.priority == .utility)
    clock.now = 100 + 1.0 / 60
    #expect(scheduler.takeFrame() == nil)
    clock.now = next.deadline
    #expect(scheduler.takeFrame() == .animation)
    #expect(scheduler.nextFrame?.deadline == clock.now + 1.0 / 30)
    scheduler.animationsActive = false
    #expect(scheduler.nextFrame == nil)
  }

  @Test func contentDemandCoalescesAndSupersedesAnimationWithinGlobalCap() throws {
    let clock = Clock()
    let scheduler = FrameScheduler(clock: { clock.now })
    scheduler.requestContent()
    #expect(scheduler.takeFrame() == .content)
    scheduler.animationsActive = true
    clock.now += 0.001
    for _ in 0..<100 { scheduler.requestContent() }
    let next = try #require(scheduler.nextFrame)
    #expect(next.kind == .content)
    #expect(next.priority == .userInitiated)
    #expect(next.deadline == 100 + 1.0 / 60)
    #expect(scheduler.takeFrame() == nil)
    clock.now = next.deadline
    #expect(scheduler.takeFrame() == .content)
    #expect(scheduler.nextFrame?.kind == .animation)
    #expect(scheduler.nextFrame?.deadline == clock.now + 1.0 / 30)
    // A content frame already advanced animations: no immediate catch-up animation frame.
    #expect(scheduler.takeFrame() == nil)
    clock.now = try #require(scheduler.nextFrame).deadline
    #expect(scheduler.takeFrame() == .animation)
    scheduler.requestContent()
    #expect(scheduler.nextFrame?.deadline == clock.now + 1.0 / 60)
    #expect(scheduler.takeFrame() == nil)
  }

  @Test func slowFramesAndLateWakeupsDoNotCatchUpWithBursts() throws {
    let clock = Clock()
    let scheduler = FrameScheduler(clock: { clock.now })
    scheduler.requestContent()
    #expect(scheduler.takeFrame() == .content)
    scheduler.animationsActive = true
    clock.now += 2
    #expect(scheduler.takeFrame() == .animation)
    #expect(scheduler.takeFrame() == nil)
    // Record completion of synchronous frame work, not just the wake-up time.
    clock.now += 0.1
    scheduler.recordProducedFrame()
    scheduler.requestContent()
    #expect(scheduler.nextFrame?.deadline == clock.now + 1.0 / 60)
    scheduler.reset()
    #expect(scheduler.nextFrame == nil)
    #expect(scheduler.lastFrameTime == nil)
  }

  @Test func rateChangesAndContentAnimationsRemainCapped() throws {
    let clock = Clock()
    let scheduler = FrameScheduler(clock: { clock.now })
    scheduler.requestContent()
    #expect(scheduler.takeFrame() == .content)
    scheduler.contentAnimationActive = true
    scheduler.setRefreshRates(minimum: 20, maximum: 40)
    #expect(scheduler.nextFrame?.deadline == 100 + 1.0 / 20)
    #expect(scheduler.nextFrame?.kind == .content)
    #expect(scheduler.nextFrame?.priority == .utility)
    scheduler.requestContent()
    #expect(scheduler.nextFrame?.deadline == 100 + 1.0 / 40)
    #expect(scheduler.nextFrame?.priority == .userInitiated)
    scheduler.setRefreshRates(minimum: 40, maximum: 40)
    clock.now = try #require(scheduler.nextFrame).deadline
    #expect(scheduler.takeFrame() == .content)
    #expect(scheduler.nextFrame?.deadline == clock.now + 1.0 / 40)
  }

  @Test func scheduledTasksUseSeparatePrioritiesAndOneGlobalCap() async {
    let scheduler = FrameScheduler()
    let clock = ContinuousClock()
    let frames = await withCheckedContinuation { continuation in
      var frames: [(FrameScheduler.FrameKind, TaskPriority, ContinuousClock.Instant)] = []
      scheduler.onFrame = { kind in
        frames.append((kind, Task.currentPriority, clock.now))
        switch frames.count {
        case 1: scheduler.animationsActive = true
        case 2: scheduler.requestContent()
        default:
          scheduler.isReady = false
          continuation.resume(returning: frames)
        }
      }
      scheduler.isReady = true
      scheduler.requestContent()
    }
    #expect(frames.map { $0.0 } == [.content, .animation, .content])
    #expect(frames.map { $0.1 } == [.userInitiated, .utility, .userInitiated])
    #expect(frames[0].2.duration(to: frames[1].2) >= .seconds(1.0 / 30))
    #expect(frames[1].2.duration(to: frames[2].2) >= .seconds(1.0 / 60))
    scheduler.reset()
  }

  @Test func readinessAndResetCancelScheduledWork() async {
    let scheduler = FrameScheduler()
    var frames = 0
    scheduler.onFrame = { _ in frames += 1 }
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
