import Chroma
import ChromaTesting
import Foundation
import InteractionFixtures

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
  @MainActor static func main() {
    for count in [100, 1_000, 5_000] {
      for lazy in [false, true] {
        for events in [1, 8] {
          for workload in InputWorkload.allCases {
            measure(count: count, lazy: lazy, events: events, workload: workload)
          }
        }
      }
    }
  }

  @MainActor private static func measure(count: Int, lazy: Bool, events: Int, workload: InputWorkload) {
    let counters = InteractionWorkloadCounters()
    let host = HeadlessHost(size: Size(width: 400, height: 600))
    let constructionStart = ProcessInfo.processInfo.systemUptime
    host.content = InteractionWorkload(count: count, lazy: lazy, counters: counters)
    let installed = ProcessInfo.processInfo.systemUptime
    host.renderScheduled()
    let coldEnd = ProcessInfo.processInfo.systemUptime
    print(String(format: "construction install=%.3f cold-frame=%.3f ms viewport=400x600",
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
    for iteration in 0..<35 {
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
      if iteration >= 5 {
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
    print("\(workload.rawValue) \(lazy ? "lazy" : "eager") rows=\(count) events/frame=\(events)")
    print(
      String(
        format: "  input p50=%.3f p95=%.3f ms; render p50=%.3f p95=%.3f ms",
        percentile(inputTimes, 0.5), percentile(inputTimes, 0.95),
        percentile(renderTimes, 0.5), percentile(renderTimes, 0.95)))
    print("  row draws/frame: input=\(inputDraws / inputTimes.count) render=\(renderDraws / renderTimes.count)")
    print("  measurements/frame: input=\(inputMeasurements / inputTimes.count) render=\(renderMeasurements / renderTimes.count)")
    print("  workload body evaluations/frame: input=\(inputEvaluations / inputTimes.count) render=\(renderEvaluations / renderTimes.count)")
    if workload == .drag {
      host.handleInput(InputState(pointerPosition: Point(x: 47, y: 54), pointerReleased: true))
      host.renderScheduled()
    }
    host.close()
  }
}
