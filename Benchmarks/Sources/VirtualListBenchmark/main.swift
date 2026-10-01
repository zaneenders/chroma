import Chroma
import ChromaTesting
import Foundation

@main
struct VirtualListBenchmark {
  @MainActor static func main() {
    print("kind,count,snapshot_ms,cold_ms,warm_p50_ms,warm_p95_ms,warm_row_builds,commands")
    for count in [1_000, 100_000, 1_000_000] {
      run(count: count, variable: false)
      run(count: count, variable: true)
    }
  }

  @MainActor static func run(count: Int, variable: Bool) {
    let start = ProcessInfo.processInfo.systemUptime
    let snapshot = VirtualListSnapshot(ids: 0..<count)
    let snapshotMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
    let host = HeadlessHost(size: Size(width: 400, height: 600))
    host.usesNodeLifecycle = true
    var builds = 0
    if variable {
      host.content = VariableHeightList(snapshot: snapshot, estimatedHeight: 80) { id in
        builds += 1
        return Text(String(repeating: "Message \(id): streaming transcript content. ", count: id % 8 + 1)).wrapping().padding(8)
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
    let previousBuilds = builds
    var timings: [Double] = []
    var commands = 0
    for _ in 0..<30 {
      let start = ProcessInfo.processInfo.systemUptime
      for _ in 0..<8 { host.handleInput(InputState(pointerPosition: Point(x: 10, y: 10))) }
      commands = host.renderScheduled().commands.count
      timings.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
    timings.sort()
    precondition(builds == previousBuilds, "Warm frames rebuilt rows")
    print("\(variable ? "variable" : "fixed"),\(count),\(snapshotMilliseconds),\(coldMilliseconds),\(timings[15]),\(timings[28]),\(builds - previousBuilds),\(commands)")
  }
}
