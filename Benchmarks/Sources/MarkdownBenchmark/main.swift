import Chroma
import ChromaMarkdown
import ChromaTesting
import Foundation

private struct Result: Encodable {
  let workload: String
  let width: Float
  let sourceBytes: Int
  let samples: Int
  let commands: Int
  let p50MS: Double
  let p95MS: Double
  let work: PipelineMetrics.Snapshot
}

@main struct MarkdownBenchmark {
  @MainActor static func main() throws {
    let paragraphs = (0..<200).map {
      "Paragraph \($0) with **bold**, `code`, café and enough text to wrap across several lines."
    }.joined(separator: "\n\n")
    let longCode = "```swift\n" + String(repeating: "abcdefghij", count: 800) + "\n```"
    let samples = 30
    var results: [Result] = []
    for (name, width, base) in [
      ("static", Float(500), paragraphs),
      ("streaming", 500, paragraphs),
      ("narrow", 36, paragraphs),
      ("long-code", 120, longCode),
    ] {
      let host = HeadlessHost(size: Size(width: width, height: 600))
      var source = base
      let initialMarkdown = MarkdownText(base)
      let initialView = ScrollView { buffer, context in initialMarkdown.build(into: &buffer, context: context) }
      host.build = { buffer, context in buffer.scrollView(initialView, context: context) }
      func render(_ index: Int) -> Int {
        source = name == "streaming" ? base + "\n\n**streaming " + String(repeating: "x", count: index + 1) : base
        if name == "streaming" {
          let markdown = MarkdownText(source)
          let view = ScrollView { buffer, context in markdown.build(into: &buffer, context: context) }
          host.build = { buffer, context in buffer.scrollView(view, context: context) }
        }
        return host.render().commands.count
      }
      PipelineMetrics.isEnabled = false
      for index in 0..<5 { _ = render(index) }
      var times: [Double] = []
      var commands = 0
      for index in 0..<samples {
        let start = ProcessInfo.processInfo.systemUptime
        commands = render(index)
        times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
      }
      PipelineMetrics.isEnabled = true
      _ = render(samples - 1)
      let work = PipelineMetrics.snapshot
      PipelineMetrics.isEnabled = false
      times.sort()
      results.append(
        Result(
          workload: name, width: width, sourceBytes: source.utf8.count, samples: samples,
          commands: commands, p50MS: times[(samples - 1) / 2],
          p95MS: times[Int(ceil(Double(samples) * 0.95)) - 1], work: work))
      host.close()
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(results), as: UTF8.self))
  }
}
