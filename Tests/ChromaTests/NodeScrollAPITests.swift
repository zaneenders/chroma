import Testing

@testable import Chroma

@MainActor
struct NodeScrollAPITests {
  @Test func uniformScrollAPIKeepsWarmInputBoundedAndRevealsFarRows() throws {
    let controller = ScrollViewController()
    var builds = 0
    let content = ScrollView(data: 0..<100_000, rowHeight: 20, controller: controller) { index in
      builds += 1
      return Text("Row \(index)")
    }
    let context = BlockContext()
    let producer = NodeFrameProducer()
    let viewport = Size(width: 100, height: 60)
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(builds < 10)
    let initial = builds
    for _ in 0..<8 { try producer.dispatch(InputState(), onChange: {}) }
    #expect(builds == initial)
    #expect(producer.paints == 0)
    controller.scrollToRow(90_000)
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(builds - initial < 20)
    #expect(producer.paint().commands.contains { if case .text(_, "Row 90000", _, _) = $0 { true } else { false } })
  }

  @Test func variableRowsUseRetainedListAndControllerRequests() throws {
    let controller = ScrollViewController()
    let rows = (0..<100).map { ScrollView.Row(id: $0, content: Text("Row \($0)").padding(4)) }
    let content = ScrollView(spacing: 3, controller: controller, rows: rows)
    let context = BlockContext()
    let producer = NodeFrameProducer()
    let viewport = Size(width: 100, height: 60)
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    controller.scrollToRow(90)
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(controller.offset > 0)
    #expect(producer.paint().commands.contains { if case .text(_, "Row 90", _, _) = $0 { true } else { false } })
  }
}
