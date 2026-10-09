import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

@MainActor
package final class FrameTimingCapture {
  package enum Phase: String, Codable, Sendable {
    case displayQueue, displayDispatch, input, momentumInput, registrationRefresh
    case reconciliation, layoutRegistration, painting, frameProduction
    case frameRequested, scheduled, schedulerWake, schedulerTake, schedulerDemandAge, readiness, frameStart, frameCPU
    case frameObservation, openGLClear, openGLSubmission, eglSwap, frameCallback
    case glInstances, glDrawCalls, glUploadCalls, glUploadBytes
    case scrollHorizontal, scrollVertical, scrollStopHorizontal, scrollStopVertical
    case fingerSource, otherSource, presented, discarded, feedbackSkipped, feedbackPending, bufferScale
  }

  package struct Presentation: Codable, Sendable {
    // Only CLOCK_MONOTONIC feedback can be compared directly with capture timestamps.
    package let time: Double?
    package let clockTime: Double
    package let refreshNanoseconds: UInt32
    package let sequence: UInt64
    package let flags: UInt32

    package init(time: Double?, clockTime: Double, refreshNanoseconds: UInt32, sequence: UInt64, flags: UInt32) {
      self.time = time
      self.clockTime = clockTime
      self.refreshNanoseconds = refreshNanoseconds
      self.sequence = sequence
      self.flags = flags
    }
  }

  package struct Event: Codable, Sendable {
    package let phase: Phase
    package let start: Double
    package let end: Double
    package let frame: Int
    package var value: Double?
    package var protocolMilliseconds: UInt32?
    package var presentation: Presentation?
    package var work: PipelineMetrics.Snapshot?
  }

  package struct Span {
    fileprivate let phase: Phase
    fileprivate let start: Double
    fileprivate let frame: Int
    fileprivate let work: PipelineMetrics.Snapshot?
  }

  package struct Snapshot: Codable, Sendable {
    package var clock = "CLOCK_MONOTONIC"
    package let capacity: Int
    package let droppedEvents: Int
    package let started: Double
    package let ended: Double
    package let events: [Event]
  }

  private let clock: @MainActor () -> Double
  private let capacity: Int
  private let started: Double
  private var events: [Event] = []
  private var droppedEvents = 0
  private var producingFrame = false
  private var inputSealed = false
  package private(set) var lastFrame = 0
  package var isFull: Bool { events.count == capacity }
  package var targetFrame: Int { producingFrame && !inputSealed ? lastFrame : lastFrame + 1 }

  package init(capacity: Int = 60_000, clock: @escaping @MainActor () -> Double = monotonicTime) {
    precondition((1...200_000).contains(capacity))
    self.capacity = capacity
    self.clock = clock
    started = clock()
    events.reserveCapacity(capacity)
  }

  package nonisolated static func monotonicTime() -> Double {
    var time = timespec()
    precondition(unsafe clock_gettime(CLOCK_MONOTONIC, &time) == 0)
    return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
  }

  package func begin(_ phase: Phase, frame: Int? = nil, countsWork: Bool = false) -> Span? {
    guard hasCapacity else { return nil }
    return Span(
      phase: phase, start: clock(), frame: frame ?? targetFrame,
      work: countsWork && PipelineMetrics.isEnabled ? PipelineMetrics.snapshot : nil)
  }

  package func end(_ span: Span?, value: Double? = nil) {
    guard let span, hasCapacity else { return }
    var event = Event(phase: span.phase, start: span.start, end: clock(), frame: span.frame, value: value)
    if let before = span.work {
      var delta = PipelineMetrics.snapshot
      delta.bodyEvaluations -= before.bodyEvaluations
      delta.measurements -= before.measurements
      delta.measurementCacheHits -= before.measurementCacheHits
      delta.textLayouts -= before.textLayouts
      delta.placements -= before.placements
      delta.registrations -= before.registrations
      delta.paints -= before.paints
      delta.drawingCommands -= before.drawingCommands
      event.work = delta
    }
    events.append(event)
  }

  package func record(
    _ phase: Phase, frame: Int? = nil, value: Double? = nil,
    protocolMilliseconds: UInt32? = nil, presentation: Presentation? = nil
  ) {
    guard hasCapacity else { return }
    let now = clock()
    events.append(
      Event(
        phase: phase, start: now, end: now, frame: frame ?? targetFrame, value: value,
        protocolMilliseconds: protocolMilliseconds, presentation: presentation))
  }

  package func startFrame() -> Span? {
    lastFrame += 1
    producingFrame = true
    inputSealed = false
    record(.frameStart, frame: lastFrame)
    return begin(.frameCPU)
  }

  package func sealFrameInput() { inputSealed = true }

  package func endFrame(_ span: Span?) {
    end(span)
    producingFrame = false
  }

  package var snapshot: Snapshot {
    Snapshot(capacity: capacity, droppedEvents: droppedEvents, started: started, ended: clock(), events: events)
  }

  private var hasCapacity: Bool {
    guard events.count < capacity else {
      droppedEvents += 1
      return false
    }
    return true
  }
}
