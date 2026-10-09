import Testing

@testable import Chroma

@MainActor
struct FramePacingTests {
  @Test(arguments: [0.008, 0.040])
  func renderingTimeCountsTowardTheFrameInterval(renderDuration: Double) async throws {
    let clock = FrameSchedulerTests.Clock()
    let scheduler = FrameScheduler(clock: { clock.now })
    defer { scheduler.reset() }
    await withCheckedContinuation { continuation in
      scheduler.onFrame = {
        clock.now += renderDuration
        scheduler.requestContent()
        scheduler.isReady = false
        continuation.resume()
      }
      scheduler.isReady = true
      scheduler.requestContent()
    }
    #expect(scheduler.lastFrameTime == 100)
    #expect(try #require(scheduler.nextFrame).deadline == 100 + 1.0 / 60)
    if renderDuration > 1.0 / 60 {
      #expect(scheduler.takeFrame())
      scheduler.requestContent()
      #expect(!scheduler.takeFrame())
    }
  }
}
