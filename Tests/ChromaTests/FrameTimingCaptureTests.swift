import Foundation
import Testing

@testable import Chroma

@MainActor
struct FrameTimingCaptureTests {
  final class Clock {
    var now = 100.0
  }

  @Test func spansAreInclusiveAndAttributeOrderedInputsToTheNextFrame() throws {
    let clock = Clock()
    let capture = FrameTimingCapture(clock: { clock.now })
    let dispatch = capture.begin(.displayDispatch)
    let input = capture.begin(.input)
    clock.now += 0.002
    capture.end(input)
    capture.end(dispatch)
    let frame = capture.startFrame()
    let paint = capture.begin(.painting)
    clock.now += 0.003
    capture.end(paint)
    capture.endFrame(frame)
    capture.record(.scrollVertical, protocolMilliseconds: UInt32.max)
    let events = capture.snapshot.events
    #expect(events.map(\.frame) == [1, 1, 1, 1, 1, 2])
    #expect(events[0].end - events[0].start == events[1].end - events[1].start)
    #expect(events.last?.protocolMilliseconds == UInt32.max)
    let encoded = try JSONEncoder().encode(capture.snapshot)
    #expect(try JSONDecoder().decode(FrameTimingCapture.Snapshot.self, from: encoded).events.count == 6)
  }

  @Test func pointerBoundariesRoundTripWithoutAdvancingRenderFrames() throws {
    let capture = FrameTimingCapture()
    capture.record(.scrollVertical)
    capture.record(.fingerSource)
    capture.record(.pointerFrame)
    capture.record(.scrollHorizontal)
    capture.record(.pointerFrame)
    let encoded = try JSONEncoder().encode(capture.snapshot)
    let events = try JSONDecoder().decode(FrameTimingCapture.Snapshot.self, from: encoded).events
    #expect(events.map(\.phase) == [.scrollVertical, .fingerSource, .pointerFrame, .scrollHorizontal, .pointerFrame])
    #expect(events.map(\.frame) == [1, 1, 1, 1, 1])
    #expect(capture.lastFrame == 0)
  }

  @Test func inputsAfterDrawListProductionBelongToTheFollowingFrame() {
    let capture = FrameTimingCapture()
    let frame = capture.startFrame()
    capture.record(.scrollVertical)
    capture.sealFrameInput()
    let swap = capture.begin(.eglSwap, frame: capture.lastFrame)
    capture.record(.scrollHorizontal)
    let input = capture.begin(.input)
    capture.end(input)
    capture.end(swap)
    capture.endFrame(frame)
    #expect(capture.snapshot.events.map(\.frame) == [1, 1, 2, 2, 1, 1])
  }

  @Test func captureRetainsACompletePrefixAndBoundsNestedSpans() {
    let clock = Clock()
    let capture = FrameTimingCapture(capacity: 2, clock: { clock.now })
    let outer = capture.begin(.displayDispatch)
    capture.record(.scrollVertical)
    capture.record(.scrollHorizontal)
    capture.end(outer)
    #expect(capture.begin(.input) == nil)
    capture.record(.frameRequested)
    #expect(capture.snapshot.events.count == 2)
    #expect(capture.snapshot.droppedEvents == 3)
    #expect(capture.isFull)
  }

  @Test func workDeltasDoNotResetOrAddInclusiveChildren() {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    let capture = FrameTimingCapture()
    PipelineMetrics.record(.bodyEvaluation, count: 10)
    let input = capture.begin(.input, countsWork: true)
    let registration = capture.begin(.registrationRefresh, countsWork: true)
    PipelineMetrics.record(.bodyEvaluation, count: 3)
    PipelineMetrics.record(.measurement, count: 4)
    capture.end(registration)
    capture.end(input)
    #expect(capture.snapshot.events[0].work?.bodyEvaluations == 3)
    #expect(capture.snapshot.events[1].work?.bodyEvaluations == 3)
    #expect(PipelineMetrics.snapshot.bodyEvaluations == 13)
  }

  @Test func runtimeCaptureDoesNotChangeInputFreshnessOrIdleScheduling() {
    let runtime = WindowRuntime()
    runtime.timingCapture = FrameTimingCapture()
    defer { runtime.reset() }
    runtime.content = Text("A timing fixture")
    let viewport = Size(width: 320, height: 200)
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    runtime.handleInput(InputState(scrollDelta: Point(x: 0, y: -20)))
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    let phases = runtime.timingCapture?.snapshot.events.map(\.phase) ?? []
    #expect(phases.contains(.input))
    #expect(phases.contains(.registrationRefresh))
    #expect(phases.contains(.reconciliation))
    #expect(phases.contains(.layoutRegistration))
    #expect(phases.contains(.painting))
    #expect(runtime.scheduler.nextFrame == nil)
    runtime.timingCapture = nil
    #expect(runtime.scheduler.timingCapture == nil)
  }
}
