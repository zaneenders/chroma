import Testing

@testable import Chroma

@MainActor
struct PipelineMetricsTests {
  @Test func disabledCaptureDoesNotRecordOrAllocateLifetimeTokens() {
    PipelineMetrics.isEnabled = false
    PipelineMetrics.reset()
    PipelineMetrics.record(.bodyEvaluation)
    PipelineMetrics.record(.drawingCommands, count: 12)
    #expect(PipelineMetrics.trackLifetime(.resolvedNode) == nil)
    #expect(PipelineMetrics.snapshot == PipelineMetrics.Snapshot())
  }

  @Test func countersAndLifetimesResetIndependently() {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    var lifetime = PipelineMetrics.trackLifetime(.resolvedNode)
    PipelineMetrics.record(.bodyEvaluation, count: 2)
    PipelineMetrics.record(.measurement, count: 3)
    PipelineMetrics.record(.measurementCacheHit)
    #expect(PipelineMetrics.snapshot.bodyEvaluations == 2)
    #expect(PipelineMetrics.snapshot.measurements == 3)
    #expect(PipelineMetrics.snapshot.measurementCacheHits == 1)
    #expect(PipelineMetrics.snapshot.liveResolvedNodes == 1)
    #expect(PipelineMetrics.snapshot.peakResolvedNodes == 1)
    PipelineMetrics.reset()
    #expect(PipelineMetrics.snapshot.bodyEvaluations == 0)
    #expect(PipelineMetrics.snapshot.liveResolvedNodes == 1)
    withExtendedLifetime(lifetime) {}
    lifetime = nil
    #expect(PipelineMetrics.snapshot.liveResolvedNodes == 0)
  }

  @Test func priorCaptureLifetimesCannotChangeNewCapture() {
    PipelineMetrics.isEnabled = true
    var oldLifetime = PipelineMetrics.trackLifetime(.observationSubscription)
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
    var lifetime = PipelineMetrics.trackLifetime(.resolvedNode)
    PipelineMetrics.record(.registration)
    PipelineMetrics.isEnabled = false
    PipelineMetrics.record(.registration)
    #expect(PipelineMetrics.snapshot.registrations == 1)
    #expect(PipelineMetrics.snapshot.liveResolvedNodes == 1)
    withExtendedLifetime(lifetime) {}
    lifetime = nil
    #expect(PipelineMetrics.snapshot.liveResolvedNodes == 0)
  }
}
