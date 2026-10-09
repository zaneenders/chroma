import Testing

@testable import Chroma

@MainActor
struct PipelineMetricsTests {
  @Test func disabledCaptureDoesNotRecordOrAllocateLifetimeTokens() {
    PipelineMetrics.isEnabled = false
    PipelineMetrics.reset()
    PipelineMetrics.record(.registration)
    PipelineMetrics.record(.layoutNode)
    PipelineMetrics.record(.bufferGrowth)
    PipelineMetrics.record(.drawingCommands, count: 12)
    #expect(PipelineMetrics.trackObservationLifetime() == nil)
    #expect(PipelineMetrics.snapshot == PipelineMetrics.Snapshot())
  }

  @Test func countersAndLifetimesResetIndependently() {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    var lifetime = PipelineMetrics.trackObservationLifetime()
    PipelineMetrics.record(.registration, count: 2)
    PipelineMetrics.record(.layoutNode, count: 5)
    PipelineMetrics.record(.bufferGrowth, count: 4)
    PipelineMetrics.record(.measurement, count: 3)
    PipelineMetrics.record(.measurementCacheHit)
    #expect(PipelineMetrics.snapshot.registrations == 2)
    #expect(PipelineMetrics.snapshot.layoutNodes == 5)
    #expect(PipelineMetrics.snapshot.bufferGrowths == 4)
    #expect(PipelineMetrics.snapshot.measurements == 3)
    #expect(PipelineMetrics.snapshot.measurementCacheHits == 1)
    #expect(PipelineMetrics.snapshot.liveObservationSubscriptions == 1)
    #expect(PipelineMetrics.snapshot.peakObservationSubscriptions == 1)
    PipelineMetrics.reset()
    #expect(PipelineMetrics.snapshot.registrations == 0)
    #expect(PipelineMetrics.snapshot.layoutNodes == 0)
    #expect(PipelineMetrics.snapshot.bufferGrowths == 0)
    #expect(PipelineMetrics.snapshot.liveObservationSubscriptions == 1)
    withExtendedLifetime(lifetime) {}
    lifetime = nil
    #expect(PipelineMetrics.snapshot.liveObservationSubscriptions == 0)
  }

  @Test func priorCaptureLifetimesCannotChangeNewCapture() {
    PipelineMetrics.isEnabled = true
    var oldLifetime = PipelineMetrics.trackObservationLifetime()
    #expect(PipelineMetrics.snapshot.liveObservationSubscriptions == 1)
    PipelineMetrics.isEnabled = false
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    #expect(PipelineMetrics.snapshot.liveObservationSubscriptions == 0)
    withExtendedLifetime(oldLifetime) {}
    oldLifetime = nil
    #expect(PipelineMetrics.snapshot.liveObservationSubscriptions == 0)
  }

  @Test func disablingStopsWorkButTracksObservedObjectRelease() {
    PipelineMetrics.isEnabled = true
    var lifetime = PipelineMetrics.trackObservationLifetime()
    PipelineMetrics.record(.registration)
    PipelineMetrics.isEnabled = false
    PipelineMetrics.record(.registration)
    #expect(PipelineMetrics.snapshot.registrations == 1)
    #expect(PipelineMetrics.snapshot.liveObservationSubscriptions == 1)
    withExtendedLifetime(lifetime) {}
    lifetime = nil
    #expect(PipelineMetrics.snapshot.liveObservationSubscriptions == 0)
  }
}
