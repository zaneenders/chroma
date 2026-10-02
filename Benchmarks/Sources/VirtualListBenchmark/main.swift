import Chroma
import ChromaTesting
import Foundation
import Observation

@Observable
@MainActor
final class Message { var text: String; init(_ text: String) { self.text = text } }

@main
struct VirtualListBenchmark {
  @MainActor static func main() {
    print("trial,workload,kind,count,snapshot_ms,cold_ms,p50_ms,p95_ms,row_builds,commands")
    for trial in 1...3 {
      for count in [1_000, 100_000, 1_000_000] {
        for workload in ["pointer", "scroll", "drag", "streaming"] {
          run(count: count, variable: false, workload: workload, trial: trial)
          run(count: count, variable: true, workload: workload, trial: trial)
        }
      }
    }
  }

  @MainActor static func run(count: Int, variable: Bool, workload: String, trial: Int) {
    let start = ProcessInfo.processInfo.systemUptime
    let snapshot = VirtualListSnapshot(ids: 0..<count)
    let snapshotMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
    let host = HeadlessHost(size: Size(width: 400, height: 600))
    host.usesNodeLifecycle = true
    var builds = 0
    var messages: [Int: Message] = [:]
    var visibleMessage: Message?
    if variable {
      host.content = VariableHeightList(snapshot: snapshot, estimatedHeight: 80) { id in
        builds += 1
        let message = messages[id] ?? Message(String(repeating: "Message \(id): streaming transcript content. ", count: id % 8 + 1))
        messages[id] = message
        visibleMessage = message
        return Text(message.text).wrapping().padding(8)
      }
    } else {
      host.content = FixedHeightList(snapshot: snapshot, rowHeight: 20) { id in
        builds += 1
        return Text("Row \(id)")
      }
    }
    let coldStart = ProcessInfo.processInfo.systemUptime
    _ = host.render()
    let coldMilliseconds = (ProcessInfo.processInfo.systemUptime - coldStart) * 1000
    host.handleInput(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -Float(count * 10))))
    _ = host.renderScheduled()
    for _ in 0..<5 { _ = host.renderScheduled() }
    if workload == "drag" {
      host.handleInput(InputState(pointerPosition: Point(x: 10, y: 10), pointerDown: true, pointerPressed: true))
    }
    let previousBuilds = builds
    var timings: [Double] = []
    var commands = 0
    for _ in 0..<30 {
      let start = ProcessInfo.processInfo.systemUptime
      if workload == "streaming", variable { visibleMessage?.text += " token" }
      for event in 0..<8 {
        host.handleInput(InputState(
          pointerPosition: Point(x: 10, y: Float(10 + event)), pointerDown: workload == "drag",
          scrollDelta: workload == "scroll" ? Point(x: 0, y: -1) : .zero))
      }
      commands = host.renderScheduled().commands.count
      timings.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
    timings.sort()
    if workload == "pointer" { precondition(builds == previousBuilds, "Warm frames rebuilt rows") }
    print("\(trial),\(workload),\(variable ? "variable" : "fixed"),\(count),\(snapshotMilliseconds),\(coldMilliseconds),\(timings[15]),\(timings[28]),\(builds - previousBuilds),\(commands)")
  }
}
