import Foundation
import Testing

@testable import NativeTrace

private func event(
  _ phase: String, _ start: Double, _ end: Double? = nil, frame: Int = 1,
  value: Double? = nil, protocolMilliseconds: UInt32? = nil,
  presentation: TraceEvent.Presentation? = nil, work: [String: Int]? = nil
) -> TraceEvent {
  TraceEvent(
    phase: phase, start: start, end: end ?? start, frame: frame, value: value,
    protocolMilliseconds: protocolMilliseconds, presentation: presentation, work: work)
}

private func trace(_ events: [TraceEvent], dropped: Int = 0, clockID: Int = 1) -> NativeTrace {
  NativeTrace(
    metadata: ["presentationSupported": true, "presentationClockID": clockID],
    capture: TraceCapture(clock: "CLOCK_MONOTONIC", droppedEvents: dropped, started: 0, ended: 10, events: events))
}

private func object(_ value: Any?) throws -> [String: Any] {
  try #require(value as? [String: Any])
}

private func metric(_ summary: [String: Any], _ group: String, _ name: String, _ key: String = "p50") throws -> Double {
  try #require(try object(try object(summary[group])[name])[key] as? Double)
}

private func approximately(_ actual: Double, _ expected: Double) -> Bool {
  abs(actual - expected) < 0.000_001
}

struct NativeTraceTests {
  @Test func percentilesAndStrictBudget() throws {
    let result = distribution([1, 2, 3, 4], budget: 3)
    #expect(result["samples"] as? Int == 4)
    #expect(result["p50"] as? Double == 2)
    #expect(result["p95"] as? Double == 4)
    #expect(result["max"] as? Double == 4)
    #expect(result["overBudget"] as? Int == 1)
    #expect(distribution([])["p95"] is NSNull)
    #expect(distribution([])["overBudget"] == nil)
  }

  @Test func nestedScopesAreNotAdded() throws {
    let spans = [
      event("input", 0, 0.005), event("registrationRefresh", 0, 0.004),
      event("input", 0.005, 0.009), event("frameCPU", 0.01, 0.015),
    ]
    #expect(approximately(unionDuration(spans), 14))
    let summary = try trace(spans + [event("frameStart", 0.01)]).summarize()
    #expect(approximately(try metric(summary, "perFrameInputAndFrameWallUnionByMode", "other"), 14))
    #expect(try object(try object(summary["phaseDurationsInclusive"])["registrationRefresh"])["samples"] as? Int == 1)
  }

  @Test func diagonalInputCorrelatesToPresentationNotCallback() throws {
    let summary = try trace([
      event("fingerSource", 0), event("scrollVertical", 0.001), event("scrollHorizontal", 0.002),
      event("input", 0.001, 0.003), event("frameStart", 0.01), event("frameCPU", 0.01, 0.012),
      event("eglSwap", 0.011, 0.012), event("frameCallback", 0.018, protocolMilliseconds: 5),
      event("presented", 0.025, presentation: .init(time: 0.020, clockTime: 0.020)),
    ]).summarize()
    #expect(try object(summary["perFrameInputAndFrameWallUnionByMode"])["finger:diagonal"] != nil)
    #expect(approximately(try metric(summary, "latencies", "axisReceiptToPresentation"), 18))
    #expect(approximately(try metric(summary, "latencies", "swapReturnToCallbackDelivery"), 6))
    #expect(approximately(try metric(summary, "latencies", "swapReturnToPresentation"), 8))
  }

  @Test func inputAfterFrameStartHasPresentationLatencyAndFailedSwapDoesNot() throws {
    var events = [
      event("frameStart", 0.01), event("scrollVertical", 0.011), event("eglSwap", 0.012, 0.013, value: 1),
      event("presented", 0.025, presentation: .init(time: 0.020, clockTime: 0.020)),
    ]
    var summary = try trace(events).summarize()
    #expect(try object(summary["latencies"])["axisReceiptToFrameStart"] == nil)
    #expect(approximately(try metric(summary, "latencies", "axisReceiptToPresentation"), 9))
    events[2].value = 0
    summary = try trace(events).summarize()
    #expect(summary["failedSwaps"] as? Int == 1)
    #expect(try object(summary["latencies"])["axisReceiptToSwapReturn"] == nil)
    #expect(try object(summary["axisEventCoverage"])["withoutSuccessfulSwap"] as? Int == 1)
  }

  @Test func unrenderedInputRemainsVisible() throws {
    var events = [
      event("scrollVertical", 1, frame: 2), event("input", 1, 2, frame: 2),
      event("registrationRefresh", 1, 2, frame: 2), event("scrollHorizontal", 2, frame: 2),
      event("input", 2, 3, frame: 2),
    ]
    var summary = try trace(events).summarize()
    #expect(
      summary["axisEventCoverage"] as? [String: Int] == [
        "received": 2, "withoutFrameStart": 2, "withoutSuccessfulSwap": 2, "withoutPresentationTime": 2,
      ])
    #expect(try object(summary["inputWallUnionWithoutFrameStart"])["p50"] as? Double == 2000)
    #expect(try object(summary["perFrameInputAndFrameWallUnionByMode"]).isEmpty)
    #expect((summary["warnings"] as? [String])?.contains { $0.contains("latency samples omit") } == true)
    events += [
      event("frameStart", 3, frame: 2), event("eglSwap", 3, 3.001, frame: 2),
      event("presented", 3.01, frame: 2, presentation: .init(time: 3.01, clockTime: 3.01)),
    ]
    summary = try trace(events).summarize()
    #expect(try object(summary["axisEventCoverage"])["withoutPresentationTime"] as? Int == 0)
    #expect(try object(summary["inputWallUnionWithoutFrameStart"])["samples"] as? Int == 0)
  }

  @Test func rangeCutFeedbackIsIncomplete() throws {
    let summary = try trace([
      event("scrollVertical", 1), event("frameStart", 1.01), event("eglSwap", 1.01, 1.02),
      event("presented", 2, presentation: .init(time: 1.03, clockTime: 1.03)),
    ]).summarize(start: 1, end: 1.5)
    #expect(
      summary["axisEventCoverage"] as? [String: Int] == [
        "received": 1, "withoutFrameStart": 0, "withoutSuccessfulSwap": 0, "withoutPresentationTime": 1,
      ])
  }

  @Test func unknownClockKeepsIntervalsButOmitsCrossClockLatency() throws {
    let summary = try trace(
      [
        event("frameStart", 0), event("eglSwap", 0, 0.001),
        event("presented", 0.01, presentation: .init(clockTime: 123)),
        event("presented", 0.02, frame: 2, presentation: .init(clockTime: 123.02)),
      ], clockID: 0
    ).summarize()
    #expect(try object(summary["latencies"])["swapReturnToPresentation"] == nil)
    #expect(
      approximately(try #require(try object(summary["presentationIntervalsIncludingIdle"])["p50"] as? Double), 20))
    #expect((summary["warnings"] as? [String])?.contains { $0.contains("clock differs") } == true)
  }

  @Test func protocolWrapIdleGapsAndDemandSlots() throws {
    let summary = try trace([
      event("frameStart", 0), event("frameCallback", 0.010, protocolMilliseconds: 0xFFFF_FFFC),
      event("scrollVertical", 0.015, frame: 2), event("frameStart", 0.050, frame: 2),
      event("frameCallback", 0.060, frame: 2, protocolMilliseconds: 6),
      event("frameRequested", 4.9, frame: 3), event("frameStart", 5, frame: 3),
    ]).summarize()
    #expect(try object(summary["continuousDemandFrameIntervals"])["samples"] as? Int == 1)
    #expect(summary["missedDemandSlots"] as? Double == 2)
    #expect(try object(summary["callbackProtocolIntervalsIncludingIdle"])["p50"] as? Double == 10)
    #expect(try object(summary["frameIntervalsIncludingIdle"])["samples"] as? Int == 2)
  }

  @Test func modeIntervalsExcludeTransitionsAndMissingIDs() throws {
    let summary = try trace([
      event("fingerSource", 0), event("scrollVertical", 0), event("frameStart", 0),
      event("scrollVertical", 0.015, frame: 2), event("frameStart", 0.02, frame: 2),
      event("momentumInput", 0.04, frame: 3), event("frameStart", 0.04, frame: 3),
      event("momentumInput", 0.07, frame: 4), event("frameStart", 0.07, frame: 4),
      event("scrollVertical", 1, frame: 5), event("frameStart", 1, frame: 5),
      event("scrollVertical", 2, frame: 7), event("frameStart", 2, frame: 7),
    ]).summarize()
    #expect(approximately(try metric(summary, "consecutiveFrameIntervalsByMode", "finger:vertical"), 20))
    #expect(
      try object(try object(summary["consecutiveFrameIntervalsByMode"])["finger:vertical"])["samples"] as? Int == 1)
    #expect(approximately(try metric(summary, "consecutiveFrameIntervalsByMode", "momentum"), 30))
    #expect(try object(summary["consecutiveFrameIntervalsByMode"])["other"] == nil)
  }

  @Test func readinessWaitIsSeparateFromReadyWait() throws {
    let summary = try trace([
      event("readiness", 0, value: 1), event("readiness", 0.01, value: 0), event("readiness", 0.025, value: 1),
      event("schedulerDemandAge", 0.03, value: 0.01), event("frameStart", 0.03),
    ]).summarize()
    #expect(approximately(try metric(summary, "latencies", "requestWaitWhileNotReady"), 5))
    #expect(approximately(try metric(summary, "latencies", "requestWaitWhileReady"), 5))
    #expect(approximately(try metric(summary, "latencies", "requestToFrameStart"), 10))
  }

  @Test func workTotalsDoNotAddNestedRegistration() throws {
    let work = ["bodyEvaluations": 5, "registrations": 9]
    let summary = try trace([event("input", 0, 0.001, work: work), event("registrationRefresh", 0, 0.001, work: work)])
      .summarize()
    for phase in ["input", "registrationRefresh"] {
      let counts = try object(try object(summary["workInclusive"])[phase])
      #expect(counts["calls"] as? Int == 1)
      #expect(try object(counts["totals"])["bodyEvaluations"] as? Int == 5)
      #expect(try object(counts["totals"])["paints"] as? Int == 0)
    }
    #expect(try object(try object(summary["workInclusive"])["frameProduction"])["calls"] as? Int == 0)
  }

  @Test func emptySaturatedAndSelectedCaptures() throws {
    var summary = try trace([], dropped: 1).summarize()
    #expect(try object(summary["frameIntervalsIncludingIdle"])["p50"] is NSNull)
    #expect((summary["warnings"] as? [String])?.contains { $0.contains("saturated") } == true)
    #expect(summary["gpuExecution"] is NSNull)
    summary = try trace([event("frameStart", 1), event("frameStart", 2, frame: 2)]).summarize(start: 2, end: 3)
    #expect(summary["capturedEvents"] as? Int == 1)
    #expect(try object(summary["frameIntervalsIncludingIdle"])["samples"] as? Int == 0)
  }

  @Test func invalidTimingSchemaClockAndRangesAreRejected() throws {
    #expect(throws: TraceError.self) { try trace([event("input", 1, 0)]).summarize() }
    for hz in [Double.nan, .infinity, 0, 1001] {
      #expect(throws: TraceError.self) { try trace([]).summarize(refreshHz: hz) }
    }
    for (start, end) in [(-1.0, 1.0), (1, 1), (Double.nan, 2), (0, Double.nan)] {
      #expect(throws: TraceError.self) { try trace([]).summarize(start: start, end: end) }
    }
    #expect(throws: TraceError.self) { try trace([event("scheduled", 0, value: .nan)]).summarize() }
    var invalid = trace([])
    invalid.schemaVersion = 2
    #expect(throws: TraceError.self) { try invalid.summarize() }
    invalid.schemaVersion = 1
    invalid.capture.clock = "other"
    #expect(throws: TraceError.self) { try invalid.summarize() }
  }

  @Test func sourceBeforeRangeAndRendererCountersArePreserved() throws {
    var report = trace([
      event("otherSource", 0), event("scrollHorizontal", 2), event("frameStart", 2),
      event("glInstances", 2, value: 20), event("glDrawCalls", 2, value: 2),
      event("glUploadCalls", 2, value: 3), event("glUploadBytes", 2, value: 512),
    ])
    report.metadata["renderer"] = ["name": "fixture", "version": 1]
    report.metadata["presentationSupported"] = false
    let summary = try report.summarize(start: 1)
    #expect(try object(summary["perFrameInputAndFrameWallUnionByMode"])["otherSource:horizontal"] != nil)
    #expect(try metric(summary, "glCounters", "glInstances") == 20)
    #expect(try metric(summary, "glCounters", "glUploadBytes") == 512)
    #expect(try object(summary["metadata"])["renderer"] as? [String: Any] != nil)
    #expect((summary["warnings"] as? [String])?.contains { $0.contains("unavailable") } == true)
    #expect(try JSONSerialization.data(withJSONObject: summary).isEmpty == false)
  }

  @Test func decodingPreservesUnsignedProtocolTimestampsAndMetadata() throws {
    let data = Data(
      """
      {"schemaVersion":1,"metadata":{"presentationSupported":true,"presentationClockID":1,"driver":"fixture"},
       "capture":{"clock":"CLOCK_MONOTONIC","started":100,"ended":110,"droppedEvents":0,"events":[
         {"phase":"frameCallback","start":101,"end":101,"frame":1,"protocolMilliseconds":4294967292},
         {"phase":"frameCallback","start":102,"end":102,"frame":2,"protocolMilliseconds":6}]}}
      """.utf8)
    let summary = try NativeTrace(data: data).summarize(start: 1, end: 3)
    #expect(try object(summary["callbackProtocolIntervalsIncludingIdle"])["p50"] as? Double == 10)
    #expect(try object(summary["metadata"])["driver"] as? String == "fixture")
    #expect(throws: (any Error).self) { try NativeTrace(data: Data("{}".utf8)) }
  }
}
