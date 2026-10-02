import Chroma
import ChromaTesting
import Foundation
import InteractionFixtures
import Logging
import ProfileRecorderServer

private func percentile(_ values: [Double], _ fraction: Double) -> Double {
  values.sorted()[Int(Double(values.count - 1) * fraction)]
}

private enum InputWorkload: String, CaseIterable {
  case pointer, scroll, drag

  func input(iteration: Int, event: Int) -> InputState {
    let point = Point(x: 40 + Float(event), y: 40 + Float(iteration % 20))
    switch self {
    case .pointer: return InputState(pointerPosition: point)
    case .scroll:
      return InputState(pointerPosition: point, scrollDelta: Point(x: 0, y: iteration % 2 == 0 ? -2 : 2))
    case .drag:
      return InputState(pointerPosition: point, pointerPressPosition: Point(x: 40, y: 40), pointerDown: true)
    }
  }
}

@main
struct InteractionBenchmark {
  @MainActor static func main() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    func option(_ name: String, default fallback: String) -> String {
      guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return fallback }
      return arguments[index + 1]
    }
    let allowed = ["--rows", "--layout", "--workload", "--events", "--diagnostics", "--replay-seconds"]
    guard arguments.count % 2 == 0,
      stride(from: 0, to: arguments.count, by: 2).allSatisfy({ allowed.contains(arguments[$0]) }),
      let count = Int(option("--rows", default: "1000")), count > 0,
      let events = Int(option("--events", default: "8")), events > 0,
      let seconds = Double(option("--replay-seconds", default: "0")), seconds >= 0, seconds <= 60,
      ["on", "off"].contains(option("--diagnostics", default: "off")),
      ["all", "eager", "lazy"].contains(option("--layout", default: "all")),
      ["all", "pointer", "scroll", "drag"].contains(option("--workload", default: "all"))
    else { throw NSError(domain: "InteractionBenchmark.arguments", code: 1) }
    let layouts = [false, true].filter {
      option("--layout", default: "all") == "all" || option("--layout", default: "all") == ($0 ? "lazy" : "eager")
    }
    let workloads = InputWorkload.allCases.filter {
      option("--workload", default: "all") == "all" || option("--workload", default: "all") == $0.rawValue
    }
    guard seconds == 0 || (layouts.count == 1 && workloads.count == 1) else {
      throw NSError(domain: "InteractionBenchmark.arguments", code: 1)
    }
    EngineDiagnostics.enabled = option("--diagnostics", default: "off") == "on"
    var server: Task<Void, Never>?
    if let pattern = ProcessInfo.processInfo.environment["PROFILE_RECORDER_SERVER_URL_PATTERN"] {
      guard pattern.hasPrefix("unix:///"), pattern.contains("{PID}"),
        ProcessInfo.processInfo.environment["PROFILE_RECORDER_SERVER_URL"] == nil
      else { throw NSError(domain: "InteractionBenchmark.arguments", code: 1) }
      server = Task.detached {
        do {
          let configuration = try await ProfileRecorderServerConfiguration.parseFromEnvironment()
          await ProfileRecorderServer(configuration: configuration).runIgnoringFailures(
            logger: Logger(label: "chroma.profile"))
        } catch { print("profile configuration failed: \(error)") }
      }
    }
    for lazy in layouts {
      for workload in workloads {
        measure(count: count, lazy: lazy, events: events, workload: workload, replaySeconds: seconds)
      }
    }
    server?.cancel()
    await server?.value
  }

  @MainActor private static func measure(
    count: Int, lazy: Bool, events: Int, workload: InputWorkload, replaySeconds: Double
  ) {
    EngineDiagnostics.reset()
    let counters = InteractionWorkloadCounters()
    counters.enabled = EngineDiagnostics.enabled
    let host = HeadlessHost(size: Size(width: 400, height: 600))
    let constructionStart = ProcessInfo.processInfo.systemUptime
    host.content = InteractionWorkload(count: count, lazy: lazy, counters: counters)
    let installed = ProcessInfo.processInfo.systemUptime
    host.renderScheduled()
    let coldEnd = ProcessInfo.processInfo.systemUptime
    print(
      String(
        format: "construction install=%.3f cold-frame=%.3f ms viewport=400x600",
        (installed - constructionStart) * 1000, (coldEnd - installed) * 1000))
    if workload == .drag {
      host.handleInput(InputState(pointerPosition: Point(x: 40, y: 40), pointerDown: true, pointerPressed: true))
      host.renderScheduled()
    }
    var inputTimes: [Double] = []
    var renderTimes: [Double] = []
    var inputMeasurements = 0
    var renderMeasurements = 0
    var inputEvaluations = 0
    var renderEvaluations = 0
    var inputDraws = 0
    var renderDraws = 0
    let replayEnd = ProcessInfo.processInfo.systemUptime + replaySeconds
    var iteration = 0
    while replaySeconds > 0 ? ProcessInfo.processInfo.systemUptime < replayEnd : iteration < 35 {
      defer { iteration += 1 }
      counters.resetDraws()
      let start = ProcessInfo.processInfo.systemUptime
      for event in 0..<events {
        host.handleInput(workload.input(iteration: iteration, event: event))
      }
      let inputEnd = ProcessInfo.processInfo.systemUptime
      let measurements = counters.rowMeasurements
      let evaluations = counters.blockEvaluations
      let draws = counters.rowDraws
      counters.resetDraws()
      host.renderScheduled()
      let end = ProcessInfo.processInfo.systemUptime
      if iteration >= 5 && replaySeconds == 0 {
        inputTimes.append((inputEnd - start) * 1000)
        renderTimes.append((end - inputEnd) * 1000)
        inputMeasurements += measurements
        renderMeasurements += counters.rowMeasurements
        inputEvaluations += evaluations
        renderEvaluations += counters.blockEvaluations
        inputDraws += draws
        renderDraws += counters.rowDraws
      }
    }
    if replaySeconds == 0 {
      print("\(workload.rawValue) \(lazy ? "lazy" : "eager") rows=\(count) events/frame=\(events)")
      print(
        String(
          format: "  input p50=%.3f p95=%.3f ms; render p50=%.3f p95=%.3f ms",
          percentile(inputTimes, 0.5), percentile(inputTimes, 0.95),
          percentile(renderTimes, 0.5), percentile(renderTimes, 0.95)))
      print("  row draws/frame: input=\(inputDraws / inputTimes.count) render=\(renderDraws / renderTimes.count)")
      print(
        "  measurements/frame: input=\(inputMeasurements / inputTimes.count) render=\(renderMeasurements / renderTimes.count)"
      )
      print(
        "  workload body evaluations/frame: input=\(inputEvaluations / inputTimes.count) render=\(renderEvaluations / renderTimes.count)"
      )
    }
    print(
      "diagnostics enabled=\(EngineDiagnostics.enabled) body=\(EngineDiagnostics.bodyEvaluations) registration=\(EngineDiagnostics.registrationPasses) primitive=\(EngineDiagnostics.primitivePaintVisits) lazy-row=\(EngineDiagnostics.visibleLazyRowVisits) focus-growth=\(EngineDiagnostics.focusArrayCapacityGrowth)"
    )
    if workload == .drag {
      host.handleInput(InputState(pointerPosition: Point(x: 47, y: 54), pointerReleased: true))
      host.renderScheduled()
    }
    host.close()
  }
}
