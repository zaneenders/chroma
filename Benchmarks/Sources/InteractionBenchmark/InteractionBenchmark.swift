import Chroma
import ChromaTesting
import Foundation
import InteractionFixtures

private func percentile(_ values: [Double], _ fraction: Double) -> Double {
  values.sorted()[Int(Double(values.count - 1) * fraction)]
}

@main
struct InteractionBenchmark {
  @MainActor static func main() {
    for count in [100, 1_000, 5_000] {
      for lazy in [false, true] {
        for events in [1, 8] {
          measure(count: count, lazy: lazy, events: events)
        }
      }
    }
  }

  @MainActor private static func measure(count: Int, lazy: Bool, events: Int) {
    let counters = InteractionWorkloadCounters()
    let host = HeadlessHost(size: Size(width: 400, height: 600))
    host.content = InteractionWorkload(count: count, lazy: lazy, counters: counters)
    host.renderScheduled()
    var inputTimes: [Double] = []
    var renderTimes: [Double] = []
    var inputDraws = 0
    var renderDraws = 0
    for iteration in 0..<35 {
      counters.resetDraws()
      let start = ProcessInfo.processInfo.systemUptime
      for event in 0..<events {
        host.handleInput(InputState(pointerPosition: Point(x: 40 + Float(event), y: 40 + Float(iteration % 20))))
      }
      let inputEnd = ProcessInfo.processInfo.systemUptime
      let draws = counters.rowDraws
      counters.resetDraws()
      host.renderScheduled()
      let end = ProcessInfo.processInfo.systemUptime
      if iteration >= 5 {
        inputTimes.append((inputEnd - start) * 1000)
        renderTimes.append((end - inputEnd) * 1000)
        inputDraws += draws
        renderDraws += counters.rowDraws
      }
    }
    print("\(lazy ? "lazy" : "eager") rows=\(count) events/frame=\(events)")
    print(
      String(
        format: "  input p50=%.3f p95=%.3f ms; render p50=%.3f p95=%.3f ms",
        percentile(inputTimes, 0.5), percentile(inputTimes, 0.95),
        percentile(renderTimes, 0.5), percentile(renderTimes, 0.95)))
    print("  row draws/frame: input=\(inputDraws / inputTimes.count) render=\(renderDraws / renderTimes.count)")
    host.close()
  }
}
