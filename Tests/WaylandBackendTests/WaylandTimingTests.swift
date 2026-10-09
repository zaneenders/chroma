import Chroma
import Foundation
import Glibc
import Testing

@testable import WaylandBackend

@MainActor
struct WaylandTimingTests {
  @Test func presentationClockMustMatchBeforeCalculatingLatency() {
    let monotonic = timing(clockID: UInt32(CLOCK_MONOTONIC))
    #expect(monotonic.time == monotonic.clockTime)
    #expect(monotonic.clockTime == Double(UInt64(1) << 32 | 7) + 0.5)
    #expect(monotonic.sequence == UInt64(2) << 32 | 3)
    #expect(monotonic.refreshNanoseconds == 16_666_667)
    #expect(monotonic.flags == 7)
    #expect(timing(clockID: UInt32(CLOCK_REALTIME)).time == nil)
    #expect(timing(clockID: nil).time == nil)
  }

  @Test func captureWritesPrivateBoundedDataAndRestoresMetrics() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("trace.json")
    let wasEnabled = PipelineMetrics.isEnabled
    PipelineMetrics.isEnabled = false
    defer { PipelineMetrics.isEnabled = wasEnabled }
    let session = try #require(
      WaylandTimingSession(
        metadata: metadata(),
        environment: [
          "CHROMA_NATIVE_TRACE": path.path, "CHROMA_NATIVE_TRACE_CAPACITY": "1",
          "CHROMA_NATIVE_TRACE_WORK": "0", "SECRET_TRANSCRIPT": "must-not-appear",
        ]))
    session.capture.record(.scrollVertical)
    session.capture.record(.scrollHorizontal)
    session.finish()
    #expect(!PipelineMetrics.isEnabled)
    let data = try Data(contentsOf: path)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let capture = try #require(json["capture"] as? [String: Any])
    #expect((capture["events"] as? [Any])?.count == 1)
    #expect(capture["droppedEvents"] as? Int == 1)
    #expect(!String(decoding: data, as: UTF8.self).contains("must-not-appear"))
    let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect(WaylandTimingSession(metadata: metadata(), environment: ["CHROMA_NATIVE_TRACE": path.path]) == nil)
    #expect(try Data(contentsOf: path) == data)
    #expect(
      WaylandTimingSession(
        metadata: metadata(),
        environment: [
          "CHROMA_NATIVE_TRACE": directory.appendingPathComponent("invalid.json").path,
          "CHROMA_NATIVE_TRACE_SECONDS": "nan",
        ]) == nil)
  }

  private func metadata() -> WaylandTimingSession.Metadata {
    WaylandTimingSession.Metadata(
      executable: "/fixture", minimumRefreshRate: 30, maximumRefreshRate: 60,
      width: 1440, height: 900, bufferScale: 2,
      glVendor: nil, glRenderer: nil, glVersion: nil, eglVendor: nil, eglVersion: nil,
      swapInterval: 1, swapIntervalAccepted: true, presentationClockID: nil, presentationSupported: false)
  }

  private func timing(clockID: UInt32?) -> FrameTimingCapture.Presentation {
    WaylandTimingSession.presentationTiming(
      clockID: clockID, secondsHigh: 1, secondsLow: 7, nanoseconds: 500_000_000,
      refresh: 16_666_667, sequenceHigh: 2, sequenceLow: 3, flags: 7)
  }
}
