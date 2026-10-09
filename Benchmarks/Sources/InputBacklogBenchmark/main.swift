import Chroma
import ChromaMarkdown
import ChromaTesting
import Foundation
import StressFixtures

#if os(Linux)
import Glibc
#else
import Darwin
#endif

private func processCPUTime() -> Double {
  var value = timespec()
  precondition(clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &value) == 0)
  return Double(value.tv_sec) + Double(value.tv_nsec) / 1_000_000_000
}

private struct SourceSample: Sendable {
  let index: Int
  let intended: Double
  let emitted: Double
}

private struct SourceResult: Sendable {
  let end: Double
  let lateness: [Double]
  let peakWaiting: Int
}

private enum ReplayError: Error {
  case sourceDropped, sourceTerminated, inputOrder
}

@main
struct InputBacklogBenchmark {
  @MainActor static func main() async throws {
    if CommandLine.arguments.contains("--help") {
      print(BacklogOptions.usage)
      return
    }
    let options = try BacklogOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    var trials: [TrialReport] = []
    for trial in 0..<options.trials { trials.append(try await replay(options, trial: trial)) }
    struct Report: Encodable {
      let benchmarkKind = "scheduled-headless-input-backlog"
      let schemaVersion = 1
      let fixtureVersion = 1
      let scope = "Real HeadlessHost runtime/scheduler; no Wayland, compositor, GPU, or physical presentation"
      let configuration: BacklogOptions
      let trials: [TrialReport]
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(Report(configuration: options, trials: trials))
    print(String(decoding: data, as: UTF8.self))
  }

  @MainActor private static func replay(_ options: BacklogOptions, trial: Int) async throws -> TrialReport {
    PipelineMetrics.isEnabled = false
    let scene =
      options.workload == "stress"
      ? StressScene(configuration: StressConfiguration(rows: options.rows, depth: options.depth)) : nil
    let host = HeadlessHost(size: StressConfiguration.viewport)
    defer { host.close() }
    if let scene {
      host.build = { buffer, context in scene.build(into: &buffer, context: context) }
    } else {
      let source = (0..<options.sections).map {
        "Paragraph \($0) with **bold**, `code`, and enough text to wrap across several lines."
      }.joined(separator: "\n\n")
      let markdown = MarkdownText(source)
      host.build = { buffer, context in
        buffer.scrollView(
          ScrollView(build: { buffer, context in
            let child = markdown.build(into: &buffer, context: context.childScope(0))
            return buffer.stack([child], axis: .vertical, context: context)
          }), context: context)
      }
    }
    _ = host.render()
    // Warm fonts and the fixture; each measured trial still owns a fresh host.
    for event in 0..<10 {
      host.sendInput(input(scene: scene, event: event))
      _ = host.renderIfNeeded()
    }
    let state = BacklogRecorder()
    host.startPresenting { frame in
      state.drawCompleted(commands: frame.commands.count, at: ProcessInfo.processInfo.systemUptime)
    }
    // Finish any warmup observation delivery before recording source timestamps.
    try await Task.sleep(for: .milliseconds(100))
    state.completions.removeAll()
    let clock = ContinuousClock()
    let epoch = clock.now
    let sourceStart = ProcessInfo.processInfo.systemUptime
    let pair = AsyncStream<SourceSample>.makeStream(bufferingPolicy: .bufferingOldest(options.events))
    let producer = Task.detached(priority: .userInitiated) {
      defer { pair.continuation.finish() }
      var lateness: [Double] = []
      var peakWaiting = 0
      for index in 0..<options.events {
        let offset = Double(index) / Double(options.inputHz)
        try await clock.sleep(until: epoch.advanced(by: .seconds(offset)))
        let emitted = ProcessInfo.processInfo.systemUptime
        let intended = sourceStart + offset
        lateness.append(emitted - intended)
        switch pair.continuation.yield(SourceSample(index: index, intended: intended, emitted: emitted)) {
        case .enqueued(let remaining): peakWaiting = max(peakWaiting, options.events - remaining)
        case .dropped: throw ReplayError.sourceDropped
        case .terminated: throw ReplayError.sourceTerminated
        @unknown default: throw ReplayError.sourceTerminated
        }
      }
      // Include the final source period, independently of consumer progress.
      try await clock.sleep(until: epoch.advanced(by: .seconds(Double(options.events) / Double(options.inputHz))))
      return SourceResult(end: ProcessInfo.processInfo.systemUptime, lateness: lateness, peakWaiting: peakWaiting)
    }
    defer { producer.cancel() }
    var expectedSample = 0
    for await sample in pair.stream {
      guard sample.index == expectedSample else { throw ReplayError.inputOrder }
      expectedSample += 1
      let vertical = input(scene: scene, event: sample.index)
      var inputs: [(String, InputState)] = [("vertical", vertical)]
      if options.axes == 2 {
        var horizontal = vertical
        horizontal.scrollDelta = Point(x: vertical.scrollDelta.y, y: 0)
        inputs.append(("horizontal", horizontal))
      }
      // One logical sample remains synchronous; diagonal axes are still two
      // fresh applications, without a manufactured yield between them.
      for (axis, event) in inputs {
        let cpuStart = processCPUTime()
        let start = ProcessInfo.processInfo.systemUptime
        host.sendInput(event)
        let end = ProcessInfo.processInfo.systemUptime
        let cpuElapsed = processCPUTime() - cpuStart
        state.applications.append(
          ApplicationRecord(
            sequence: state.applications.count, logicalSample: sample.index, axis: axis,
            intendedSourceTime: sample.intended, emittedTime: sample.emitted,
            start: start, end: end, firstDrawCompletion: nil, processCPUSeconds: cpuElapsed))
      }
    }
    guard expectedSample == options.events else { throw ReplayError.inputOrder }
    let inputDrainEnd = state.applications.last?.end ?? ProcessInfo.processInfo.systemUptime
    let source = try await producer.value
    // A bounded reporting tail preserves missing-frame coverage on regressions.
    // Its duration is not a pass/fail latency threshold.
    let recoveryDeadline = clock.now.advanced(by: .seconds(5))
    while state.nextUnrendered < state.applications.count && clock.now < recoveryDeadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    let idleStarted = ProcessInfo.processInfo.systemUptime
    let idleDeadline = clock.now.advanced(by: .seconds(3))
    var quiet = 0.0
    repeat {
      try await Task.sleep(for: .milliseconds(100))
      quiet = ProcessInfo.processInfo.systemUptime - max(idleStarted, state.completions.last ?? idleStarted)
    } while quiet < 0.5 && clock.now < idleDeadline
    return TrialReport(
      trial: trial, applications: state.applications, drawCompletions: state.completions,
      sourceStart: sourceStart, sourceEnd: source.end, inputDrainEnd: inputDrainEnd,
      sourceLateness: source.lateness, peakWaitingLogicalSamples: source.peakWaiting,
      idleQuietSeconds: quiet, idleEstablished: quiet >= 0.5 && state.nextUnrendered == state.applications.count,
      drawCommands: state.commands)
  }

  @MainActor private static func input(scene: StressScene?, event: Int) -> InputState {
    if let scene { return scene.scrollInput(event: event) }
    return InputState(
      pointerPosition: Point(x: 400, y: 400), scrollDelta: Point(x: 0, y: event % 2 == 0 ? -60 : 60))
  }
}
