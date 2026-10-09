import CEGL
import CGLES3
import Chroma
import Foundation
import Glibc

@MainActor
final class WaylandTimingSession {
  struct Metadata: Encodable {
    let executable: String
    let minimumRefreshRate: Double
    let maximumRefreshRate: Double
    let width: Int32
    let height: Int32
    let bufferScale: Int32
    let glVendor: String?
    let glRenderer: String?
    let glVersion: String?
    let eglVendor: String?
    let eglVersion: String?
    var workCounters = true
    let swapInterval: Int
    let swapIntervalAccepted: Bool
    var presentationClockID: UInt32?
    var presentationSupported: Bool
  }

  private struct Report: Encodable {
    let schemaVersion = 1
    let metadata: Metadata
    let capture: FrameTimingCapture.Snapshot
  }

  let capture: FrameTimingCapture
  let duration: Double
  var metadata: Metadata
  private let path: String
  private let previouslyEnabledMetrics: Bool

  static var isRequested: Bool {
    !(ProcessInfo.processInfo.environment["CHROMA_NATIVE_TRACE"] ?? "").isEmpty
  }

  init?(metadata: Metadata, environment: [String: String] = ProcessInfo.processInfo.environment) {
    guard let path = environment["CHROMA_NATIVE_TRACE"], !path.isEmpty else { return nil }
    guard let duration = Double(environment["CHROMA_NATIVE_TRACE_SECONDS"] ?? "30"),
      duration.isFinite, (0.1...300).contains(duration),
      let capacity = Int(environment["CHROMA_NATIVE_TRACE_CAPACITY"] ?? "60000"),
      (1...200_000).contains(capacity),
      ["0", "1"].contains(environment["CHROMA_NATIVE_TRACE_WORK"] ?? "1"),
      !FileManager.default.fileExists(atPath: path)
    else {
      Self.warn("native trace disabled: invalid duration/capacity or output already exists")
      return nil
    }
    self.path = path
    self.duration = duration
    self.metadata = metadata
    previouslyEnabledMetrics = PipelineMetrics.isEnabled
    self.metadata.workCounters = environment["CHROMA_NATIVE_TRACE_WORK"] != "0" || previouslyEnabledMetrics
    if self.metadata.workCounters { PipelineMetrics.isEnabled = true }
    capture = FrameTimingCapture(capacity: capacity)
  }

  @diagnose(StrictMemorySafety, as: ignored, reason: "GL/EGL return context-owned, NUL-terminated driver strings.")
  static func metadata(
    minimum: Double, maximum: Double, width: Int32, height: Int32, scale: Int32,
    display: EGLDisplay?, swapIntervalAccepted: Bool, presentationSupported: Bool, presentationClockID: UInt32?
  ) -> Metadata {
    func glString(_ name: Int32) -> String? {
      guard let bytes = glGetString(GLenum(name)) else { return nil }
      return unsafe String(cString: bytes)
    }
    func eglString(_ name: Int32) -> String? {
      guard let bytes = unsafe eglQueryString(display, name) else { return nil }
      return unsafe String(cString: bytes)
    }
    return Metadata(
      executable: CommandLine.arguments.first ?? "unknown",
      minimumRefreshRate: minimum, maximumRefreshRate: maximum,
      width: width, height: height, bufferScale: scale,
      glVendor: glString(GL_VENDOR), glRenderer: glString(GL_RENDERER), glVersion: glString(GL_VERSION),
      eglVendor: eglString(EGL_VENDOR), eglVersion: eglString(EGL_VERSION), swapInterval: 1,
      swapIntervalAccepted: swapIntervalAccepted,
      presentationClockID: presentationClockID, presentationSupported: presentationSupported)
  }

  static func presentationTiming(
    clockID: UInt32?, secondsHigh: UInt32, secondsLow: UInt32, nanoseconds: UInt32,
    refresh: UInt32, sequenceHigh: UInt32, sequenceLow: UInt32, flags: UInt32
  ) -> FrameTimingCapture.Presentation {
    let time = Double(UInt64(secondsHigh) << 32 | UInt64(secondsLow)) + Double(nanoseconds) / 1_000_000_000
    return FrameTimingCapture.Presentation(
      time: clockID == UInt32(CLOCK_MONOTONIC) ? time : nil, clockTime: time,
      refreshNanoseconds: refresh, sequence: UInt64(sequenceHigh) << 32 | UInt64(sequenceLow), flags: flags)
  }

  func finish() {
    let snapshot = capture.snapshot
    PipelineMetrics.isEnabled = previouslyEnabledMetrics
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let data = try encoder.encode(Report(metadata: metadata, capture: snapshot))
      let fd = path.withCString { unsafe open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o600)) }
      guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
      let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
      try file.write(contentsOf: data)
      try file.close()
    } catch {
      Self.warn("could not write native trace")
    }
  }

  private static func warn(_ message: String) {
    try? FileHandle.standardError.write(contentsOf: Data(("Chroma: " + message + "\n").utf8))
  }
}
