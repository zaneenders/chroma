import Chroma
import ChromaTesting
import Foundation

@MainActor private final class Counter { var emissions = 0 }

@MainActor
private func row(_ index: Int, counter: Counter, into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode
{
  counter.emissions += 1
  return buffer.background(
    context: context,
    content: { buffer, context in
      let title = buffer.text(Text("Session \(index)"), context: context.childScope(0))
      let spacer = buffer.spacer(context: context.childScope(1))
      let status = buffer.text(Text("Ready"), context: context.childScope(2))
      let stack = buffer.stack([title, spacer, status], axis: .horizontal, spacing: 4, context: context)
      return buffer.padding(stack, 4, context: context)
    }, background: { buffer, context in buffer.color(.black, context: context) })
}

@MainActor
private func layers(
  _ depth: Int, interactive: Bool, counter: Counter, into buffer: inout LayoutBuffer, context: LayoutContext
) -> LayoutNode {
  guard depth > 0 else {
    let rows = (0..<20).map { row($0, counter: counter, into: &buffer, context: context.childScope($0)) }
    return buffer.stack(rows, axis: .vertical, context: context)
  }
  return buffer.group(context: context) { buffer, context in
    let childContext = context.childScope(0).childScope(0).childScope(0)
    let child: LayoutNode
    if interactive {
      child = buffer.interactive(
        action: {},
        content: { buffer, context, _ in
          layers(depth - 1, interactive: interactive, counter: counter, into: &buffer, context: context)
        }, context: childContext)
    } else {
      child = layers(depth - 1, interactive: interactive, counter: counter, into: &buffer, context: childContext)
    }
    let vertical = buffer.stack([child], axis: .vertical, context: context.childScope(0).childScope(0))
    let padded = buffer.padding(vertical, 2, context: context.childScope(0))
    let sized = buffer.sizing(padded, x: .grow, context: context.childScope(0))
    return buffer.stack([sized], axis: .horizontal, context: context)
  }
}

private struct Result: Encodable {
  let interactive: Bool
  let depth: Int
  let input: String
  let rows: Int
  let frames: Int
  let commands: Int
  let bodiesPerFrame: Double
  let p50MS: Double
  let p95MS: Double
}

@main struct LayoutBenchmark {
  @MainActor static func main() throws {
    let frames = 20
    let interactive = CommandLine.arguments.contains("--interactive")
    var results: [Result] = []
    for depth in [1, 3, 5] {
      for scrolling in [false, true] {
        let counter = Counter()
        let host = HeadlessHost(size: Size(width: 400, height: 300))
        host.build = { buffer, context in
          buffer.scrollView(
            ScrollView(build: { buffer, context in
              let child = layers(
                depth, interactive: interactive, counter: counter, into: &buffer, context: context.childScope(0))
              return buffer.stack([child], axis: .vertical, context: context)
            }), context: context)
        }
        let input = InputState(
          pointerPosition: Point(x: 10, y: 10),
          scrollDelta: scrolling ? Point(x: 0, y: -1) : .zero)
        for _ in 0..<3 { host.render(input: input) }
        counter.emissions = 0
        var timings: [Double] = []
        var commands = 0
        for _ in 0..<frames {
          let start = ProcessInfo.processInfo.systemUptime
          commands = host.render(input: input).commands.count
          timings.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        timings.sort()
        results.append(
          Result(
            interactive: interactive, depth: depth, input: scrolling ? "scroll" : "none", rows: 20, frames: frames,
            commands: commands, bodiesPerFrame: Double(counter.emissions) / Double(frames),
            p50MS: timings[(frames - 1) / 2], p95MS: timings[Int(ceil(Double(frames) * 0.95)) - 1]))
        host.close()
      }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(results), as: UTF8.self))
  }
}
