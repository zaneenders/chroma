import Chroma
import ChromaTesting
import Foundation

@MainActor private final class Counter { var emissions = 0 }

private struct Row: Block {
  let index: Int
  let counter: Counter

  @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    counter.emissions += 1
    return buffer.emit(content(), context: context.component(Self.self))
  }

  @MainActor private func content() -> some Block {
    HStack(spacing: 4) {
      Text("Session \(index)")
      Spacer()
      Text("Ready")
    }.padding(4).background(Color.black)
  }
}

private struct Layer: Block {
  let child: any Block

  @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    buffer.emit(content(), context: context.component(Self.self))
  }

  @MainActor private func content() -> some Block {
    Group {
      HStack {
        VStack { child }.padding(2).sizing(x: .grow)
      }
    }
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
        var content: any Block = VStack {
          for index in 0..<20 { Row(index: index, counter: counter) }
        }
        for _ in 0..<depth {
          if interactive {
            let child = content
            content = Interactive(action: {}, content: { _ in TupleBlock(children: [child]) })
          }
          content = Layer(child: content)
        }
        let host = HeadlessHost(size: Size(width: 400, height: 300))
        host.setContent(ScrollView { content })
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
