import Chroma
import Foundation
import RegistrationFixtures

private struct Configuration: Encodable {
  var rows = 10_000
  var samples = 40
  var warmup = 5
  var idlePolls = 1_000
  let viewportWidth = 480
  let viewportHeight = 360
  let rowHeight = 30
  let rowSpacing = 1
}

private struct Sample {
  let mode: RegistrationMode
  let phase: String
  let elapsedMS: Double
  let metrics: PipelineMetrics.Snapshot
  let rowConstructions: Int
  let frameCommands: Int
}

private struct Work: Encodable {
  let bodyEvaluations: Double
  let measurements: Double
  let measurementCacheHits: Double
  let measurementComputations: Double
  let placements: Double
  let registrations: Double
  let paints: Double
  let drawingCommands: Double
  let rowConstructions: Double
  let frameCommands: Double
  let maxLiveResolvedNodesAtBoundary: Int
  let maxLiveObservationSubscriptionsAtBoundary: Int
  let peakResolvedNodes: Int
  let peakObservationSubscriptions: Int
}

private struct Result: Encodable {
  let mode: RegistrationMode
  let phase: String
  let samples: Int
  let p50MS: Double
  let p95MS: Double
  let minimumMS: Double
  let maximumMS: Double
  let workPerSample: Work
}

private struct Report: Encodable {
  let configuration: Configuration
  let notes: [String]
  let results: [Result]
}

@MainActor
private func measure(
  _ phase: String,
  fixture: RegistrationFixture,
  mode: RegistrationMode,
  instrumented: Bool,
  operation: () -> Int
) -> Sample {
  if instrumented { PipelineMetrics.reset() }
  let rowsBefore = fixture.rowConstructions
  let start = ProcessInfo.processInfo.systemUptime
  let commands = operation()
  let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000
  return Sample(
    mode: mode, phase: phase, elapsedMS: elapsed,
    metrics: instrumented ? PipelineMetrics.snapshot : PipelineMetrics.Snapshot(),
    rowConstructions: fixture.rowConstructions - rowsBefore, frameCommands: commands)
}

@MainActor
private func capture(_ configuration: Configuration, instrumented: Bool) -> [Sample] {
  var results: [Sample] = []
  for sampleIndex in 0..<configuration.samples {
    // Alternate mode order within each replay to reduce monotonic timing drift.
    let modes: [RegistrationMode] =
      sampleIndex.isMultiple(of: 2) ? RegistrationMode.allCases : Array(RegistrationMode.allCases.reversed())
    for mode in modes {
      PipelineMetrics.isEnabled = instrumented
      let fixture = RegistrationFixture(mode: mode, rows: configuration.rows)
      results.append(
        measure("initial-frame", fixture: fixture, mode: mode, instrumented: instrumented) {
          fixture.host.renderIfNeeded()!.commands.count
        })
      fixture.selectIncrement()
      for _ in 0..<configuration.warmup {
        fixture.activateTwice()
        fixture.scroll()
        _ = fixture.host.renderIfNeeded()
      }
      results.append(
        measure("pre-input-two-activations", fixture: fixture, mode: mode, instrumented: instrumented) {
          fixture.activateTwice()
          return 0
        })
      results.append(
        measure("pre-input-scroll", fixture: fixture, mode: mode, instrumented: instrumented) {
          fixture.scroll()
          return 0
        })
      let actionsBeforePresentation = fixture.actions
      results.append(
        measure("active-presentation", fixture: fixture, mode: mode, instrumented: instrumented) {
          fixture.host.renderIfNeeded()!.commands.count
        })
      precondition(fixture.actions == actionsBeforePresentation, "Presentation replayed an input action")
      results.append(
        measure("idle-scheduler-polls", fixture: fixture, mode: mode, instrumented: instrumented) {
          for _ in 0..<configuration.idlePolls {
            precondition(fixture.host.renderIfNeeded() == nil, "Idle fixture scheduled a frame")
          }
          return 0
        })
      fixture.close()
      if instrumented {
        let afterClose = PipelineMetrics.snapshot
        precondition(afterClose.liveResolvedNodes == 0, "Resolved nodes outlived the closed fixture")
        precondition(afterClose.liveObservationSubscriptions == 0, "Observation subscriptions outlived the fixture")
      }
      PipelineMetrics.isEnabled = false
    }
  }
  return results
}

private func summarize(timings: [Sample], counters: [Sample]) -> [Result] {
  let phases = [
    "initial-frame", "pre-input-two-activations", "pre-input-scroll", "active-presentation",
    "idle-scheduler-polls",
  ]
  return RegistrationMode.allCases.flatMap { mode in
    phases.map { phase in
      let times = timings.filter { $0.mode == mode && $0.phase == phase }.map(\.elapsedMS).sorted()
      let work = counters.filter { $0.mode == mode && $0.phase == phase }
      func mean(_ keyPath: KeyPath<PipelineMetrics.Snapshot, Int>) -> Double {
        Double(work.reduce(0) { $0 + $1.metrics[keyPath: keyPath] }) / Double(work.count)
      }
      func peak(_ keyPath: KeyPath<PipelineMetrics.Snapshot, Int>) -> Int {
        work.map { $0.metrics[keyPath: keyPath] }.max() ?? 0
      }
      return Result(
        mode: mode, phase: phase, samples: times.count,
        p50MS: times[(times.count - 1) / 2], p95MS: times[Int(ceil(Double(times.count) * 0.95)) - 1],
        minimumMS: times.first!, maximumMS: times.last!,
        workPerSample: Work(
          bodyEvaluations: mean(\.bodyEvaluations), measurements: mean(\.measurements),
          measurementCacheHits: mean(\.measurementCacheHits),
          measurementComputations: mean(\.measurements) - mean(\.measurementCacheHits),
          placements: mean(\.placements),
          registrations: mean(\.registrations), paints: mean(\.paints),
          drawingCommands: mean(\.drawingCommands),
          rowConstructions: Double(work.reduce(0) { $0 + $1.rowConstructions }) / Double(work.count),
          frameCommands: Double(work.reduce(0) { $0 + $1.frameCommands }) / Double(work.count),
          maxLiveResolvedNodesAtBoundary: peak(\.liveResolvedNodes),
          maxLiveObservationSubscriptionsAtBoundary: peak(\.liveObservationSubscriptions),
          peakResolvedNodes: peak(\.peakResolvedNodes),
          peakObservationSubscriptions: peak(\.peakObservationSubscriptions)))
    }
  }
}

@main
private struct RegistrationBenchmark {
  @MainActor static func main() throws {
    var configuration = Configuration()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
      let argument = arguments.removeFirst()
      if argument == "--help" {
        print("RegistrationBenchmark [--rows N] [--samples N] [--warmup N] [--idle-polls N]")
        return
      }
      guard !arguments.isEmpty, let value = Int(arguments.removeFirst()), value >= 0 else {
        throw ConfigurationError.invalidArgument(argument)
      }
      switch argument {
      case "--rows" where value > 0: configuration.rows = value
      case "--samples" where value > 0: configuration.samples = value
      case "--warmup": configuration.warmup = value
      case "--idle-polls" where value > 0: configuration.idlePolls = value
      default: throw ConfigurationError.invalidArgument(argument)
      }
    }
    // Timing and counters use separate, identical replays. Mutex/token overhead is
    // never included in the published timings.
    PipelineMetrics.isEnabled = false
    let timings = capture(configuration, instrumented: false)
    let counters = capture(configuration, instrumented: true)
    let report = Report(
      configuration: configuration,
      notes: [
        "Same binary, dataset, viewport, warmup and ordered input sequence for both modes.",
        "Timing replay disables PipelineMetrics; a separate identical replay collects work counters.",
        "Legacy mode adds one identity-preserving custom primitive to force the draw-to-register adapter. It is a same-binary mechanism baseline, not a historical executable comparison.",
        "Initial-frame samples use fresh hosts and exclude fixture allocation; they are not process-cold startup timings.",
        "Pre-input activation samples contain two distinct events with no intervening presentation; each captured callback must observe its predecessor's update.",
        "Active presentation coalesces the two activations and scroll event. Presentation is asserted not to replay actions.",
        "Idle samples check scheduling synchronously and require zero frames. They do not measure native idle CPU or asynchronous event-loop delivery.",
        "The fixture uses 30-point identified virtualized rows with 1-point spacing. Identity scans still cover all rows on each deferred-root evaluation.",
        "measurementComputations is resolved measurement requests minus cache hits. It is not a count of only primitive measurements.",
        "Resolved nodes and proposal measurement caches remain traversal-scoped. Each event conservatively reconciles current content and callbacks.",
        "Each closed fixture is checked for zero observed live resolved nodes and observation subscription objects.",
      ], results: summarize(timings: timings, counters: counters))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
  }
}

private enum ConfigurationError: Error {
  case invalidArgument(String)
}
