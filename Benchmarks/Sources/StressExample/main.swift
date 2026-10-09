import Chroma
import ChromaApp
import ChromaMarkdown
import Foundation
import StressFixtures

@main
struct StressExample: NativeApp {
  private let stress: StressScene
  private let controller = ScrollViewController()
  private let markdown: String
  private let workload: String
  private let minimum: Double
  private let maximum: Double

  init() {
    let environment = ProcessInfo.processInfo.environment
    workload = environment["CHROMA_STRESS_WORKLOAD"] ?? "identified"
    precondition(["identified", "plain", "markdown"].contains(workload))
    let rows = Int(environment["CHROMA_STRESS_ROWS"] ?? "100000")!
    let panes = Int(environment["CHROMA_STRESS_PANES"] ?? "3")!
    let depth = Int(environment["CHROMA_STRESS_DEPTH"] ?? "8")!
    let sections = Int(environment["CHROMA_STRESS_MARKDOWN_SECTIONS"] ?? "200")!
    precondition(
      (1...1_000_000).contains(rows) && (1...8).contains(panes)
        && (0...16).contains(depth) && (1...2000).contains(sections))
    minimum = Double(environment["CHROMA_STRESS_MIN_HZ"] ?? "30")!
    maximum = Double(environment["CHROMA_STRESS_MAX_HZ"] ?? "60")!
    stress = StressScene(
      configuration: StressConfiguration(rows: rows, panes: panes, depth: depth), identifiedRows: workload != "plain")
    markdown = (0..<sections).map { index in
      """
      ## Transcript section \(index)
      A synthetic assistant response with **emphasis**, `inline code`, and a longer paragraph to wrap across the pane.

      - Inspect input dispatch and ordered registration.
      - Separate CPU work from compositor presentation.

      ```swift
      let frame = renderCurrentContent()
      submit(frame)
      ```

      | Phase | Boundary |
      | --- | --- |
      | Layout | Prepared current content |
      | Rendering | Ordered draw commands |

      """
    }.joined(separator: "\n")
    let settings =
      "workload=\(workload) rows=\(rows) panes=\(panes) depth=\(depth) markdownSections=\(sections) minHz=\(minimum) maxHz=\(maximum)\n"
    try? FileHandle.standardError.write(contentsOf: Data(settings.utf8))
  }

  var windowSize: Size { StressConfiguration.viewport }
  var minimumRefreshRate: Double { minimum }
  var maximumRefreshRate: Double { maximum }

  var body: some Block {
    if workload != "markdown" {
      stress.content
    } else {
      ScrollView(controller: controller) {
        MarkdownText(markdown).sizing(x: .fixed(1800))
      }
    }
  }
}
