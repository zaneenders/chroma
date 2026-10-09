import Chroma
import ChromaTesting
import Foundation

@main
struct TextSelectionBenchmark {
  @MainActor static func main() {
    // Command counts are deterministic; timings are diagnostic headless samples.
    // Run with -c release and without competing builds or profiling processes.
    for lineCount in [10, 50, 100] {
      let host = HeadlessHost(size: Size(width: 800, height: 600))
      let target = FocusTarget()
      let text = Array(repeating: String(repeating: "a", count: 80), count: lineCount).joined(separator: "\n")
      host.build = { buffer, context in
        buffer.focus(target, context: context) { buffer, context in
          buffer.text(Text(text).selectable(), context: context)
        }
      }
      let before = host.render().commands.count
      target.focus()
      host.render()
      host.sendInput(InputState(commands: [.navigation(.stepIn)]))
      host.sendInput(InputState(textEvents: [.selectAll]))
      for _ in 0..<5 { host.render() }
      var milliseconds: [Double] = []
      var commands = 0
      for _ in 0..<20 {
        let start = ProcessInfo.processInfo.systemUptime
        let frame = host.render()
        milliseconds.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        commands = frame.commands.count
      }
      milliseconds.sort()
      print(
        "lines=\(lineCount) before=\(before) selected=\(commands) "
          + "render_p50_ms=\(milliseconds[9]) render_p95_ms=\(milliseconds[18])")
      host.close()
    }
  }
}
