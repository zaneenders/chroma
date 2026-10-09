import Chroma
import ChromaTesting
import Foundation
import StressFixtures

#if os(Linux)
import Glibc
#else
import Darwin
#endif

// Process CPU time separates traversal cost from descheduling on shared hosts.
// It is not input latency; elapsed wall time remains the primary report metric.
private func cpuTime() -> Double {
  var time = timespec()
  precondition(clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &time) == 0)
  return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
}

private struct Phase: Encodable {
  let name: String
  let samples: Int
  let p50MS: Double
  let p95MS: Double
  let cpuP50MS: Double
  let cpuP95MS: Double
  let work: PipelineMetrics.Snapshot
}

private struct Report: Encodable {
  let benchmarkKind = "stress"
  let schemaVersion = 1
  let fixtureVersion = 2
  let viewport = StressConfiguration.viewport
  let configuration: StressConfiguration
  let samples: Int
  let warmup: Int
  let commands: Int
  let phases: [Phase]

  let phaseSamples: [String: Int]
  let timings: [String: [String: Double]]

}

@main
struct StressBenchmark {
  @MainActor static func main() throws {
    if CommandLine.arguments.contains("--help") {
      print(StressOptions.usage)
      return
    }
    let options = try StressOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    let names = ["initial-frame", "input-burst", "presentation", "idle-1000-polls"]
    var timings = Array(repeating: [Double](), count: names.count)
    var cpuTimings = Array(repeating: [Double](), count: names.count)
    var work = Array(repeating: PipelineMetrics.Snapshot(), count: names.count)
    var commands = 0

    // Replay from fresh hosts so instrumentation cannot perturb the timed workload.
    for instrumented in [false, true] {
      PipelineMetrics.isEnabled = instrumented
      let scene = StressScene(configuration: options.configuration)
      let host = HeadlessHost(size: StressConfiguration.viewport)
      host.content = DeferredBlock { scene.content }
      func phase(_ index: Int, record: Bool, _ operation: () -> Void) {
        if instrumented { PipelineMetrics.reset() }
        let cpuStart = cpuTime()
        let start = ProcessInfo.processInfo.systemUptime
        operation()
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        let cpuElapsed = (cpuTime() - cpuStart) * 1000
        if record {
          if instrumented {
            work[index] = PipelineMetrics.snapshot
          } else {
            timings[index].append(elapsed)
            cpuTimings[index].append(cpuElapsed)
          }
        }
      }
      phase(0, record: true) { commands = host.render().commands.count }
      host.sendInput(InputState(commands: [.navigation(.nextFocus)]))
      let cycles = instrumented ? options.warmup + 1 : options.warmup + options.samples
      for cycle in 0..<cycles {
        let record = cycle >= options.warmup
        let before = scene.actions
        phase(1, record: record) {
          host.sendInput(InputState(commands: [.action(.activate)]))
          host.sendInput(InputState(commands: [.action(.activate)]))
          for event in 0..<options.configuration.events {
            host.sendInput(scene.scrollInput(event: event))
          }
        }
        precondition(scene.actions == before + 2, "Input reused a stale callback")
        phase(2, record: record) {
          guard let frame = host.renderIfNeeded() else { preconditionFailure("Missing presentation") }
          commands = frame.commands.count
        }
        precondition(scene.actions == before + 2, "Presentation replayed an action")
        phase(3, record: record) {
          for _ in 0..<1000 { precondition(host.renderIfNeeded() == nil, "Idle produced a frame") }
        }
      }
      host.close()
      if instrumented {
        precondition(PipelineMetrics.snapshot.liveResolvedNodes == 0)
        precondition(PipelineMetrics.snapshot.liveObservationSubscriptions == 0)
      }
      PipelineMetrics.isEnabled = false
    }
    let phases = names.indices.map { index in
      let sorted = timings[index].sorted()
      let cpuSorted = cpuTimings[index].sorted()
      return Phase(
        name: names[index], samples: sorted.count, p50MS: sorted[(sorted.count - 1) / 2],
        p95MS: sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1],
        cpuP50MS: cpuSorted[(cpuSorted.count - 1) / 2],
        cpuP95MS: cpuSorted[Int(ceil(Double(cpuSorted.count) * 0.95)) - 1], work: work[index])
    }
    let report = Report(
      configuration: options.configuration, samples: options.samples,
      warmup: options.warmup, commands: commands, phases: phases,
      phaseSamples: Dictionary(uniqueKeysWithValues: phases.map { ($0.name, $0.samples) }),
      timings: Dictionary(uniqueKeysWithValues: phases.map { ($0.name, ["p50MS": $0.p50MS, "p95MS": $0.p95MS]) }))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
  }
}
