import Testing

@testable import Chroma

@MainActor
struct NodeCompositionTests {
  private final class Counts { var prepares = 0; var paints = 0 }
  private struct Element: LifecycleElement {
    let counts: Counts
    var focusRule: FocusRule { .control }
    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { Size(width: 20, height: 20) }
    func prepareInteraction(in rect: Rect, context: BlockContext) {
      counts.prepares += 1
      _ = context.buttonState(id: context.widgetID, in: rect)
    }
    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      counts.paints += 1
      list.fillRect(rect, color: .white)
    }
  }

  @Test func customElementSeparatesPreparationAndPaint() throws {
    let counts = Counts()
    let scene = NodeScene()
    let context = BlockContext()
    try scene.update(Element(counts: counts), context: context)
    let rect = Rect(x: 0, y: 0, width: 80, height: 80)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(counts.prepares == 1)
    #expect(counts.paints == 0)
    for _ in 0..<8 { try scene.dispatch(InputState()) }
    #expect(counts.prepares == 1)
    #expect(counts.paints == 0)
    _ = scene.paint()
    #expect(counts.prepares == 1)
    #expect(counts.paints == 1)
  }

  @Test func groupsTrailingControlsAndScrollMatchLegacyCommands() throws {
    let content: [any Block] = [
      Group("Panel") { Button("Run") {} },
      TrailingControlsRow(spacing: 4, input: { Text("Input") }, controls: { Button("Run") {} }),
      ScrollView { ForEach(0..<20, id: \.self) { Text("Row \($0)") } },
    ]
    for block in content {
      let context = BlockContext()
      let scene = NodeScene()
      let rect = Rect(x: 0, y: 0, width: 100, height: 40)
      try scene.update(block, context: context)
      try scene.layout(in: rect)
      scene.prepare(viewport: rect.size)
      let actual = scene.paint(cullingEnabled: false)
      context.interaction.beginFrame(input: InputState(), processingInput: false)
      var expected = DrawList()
      BlockEngine.draw(block, into: &expected, in: rect, context: context)
      context.interaction.endFrame()
      #expect(actual.commands == expected.commands)
    }
  }

  @Test func scrollDispatchReusesLoweredContentWithoutPainting() throws {
    let context = BlockContext()
    let producer = NodeFrameProducer()
    let content = ScrollView {
      ForEach(0..<100, id: \.self) { Text("Row \($0)") }
    }
    try producer.refresh(content: content, viewport: Size(width: 100, height: 40), context: context, onChange: {})
    let builds = producer.builds
    let textLayouts = producer.textLayoutBuilds
    for _ in 0..<8 {
      try producer.dispatch(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -10)), onChange: {})
    }
    #expect(producer.builds == builds)
    #expect(producer.textLayoutBuilds == textLayouts)
    #expect(producer.paints == 0)
    #expect(context.interaction.scrollStates.values.contains { $0.offset.y > 0 })
  }

  @Test func wrappedTextMeasurementAndPlacementShareBoundedLayoutCache() throws {
    let scene = NodeScene()
    let context = BlockContext()
    try scene.update(Text("A wrapped message with multiple lines of content").wrapping(), context: context)
    for width: Float in [80, 100, 80, 100] {
      try scene.layout(in: Rect(x: 0, y: 0, width: width, height: 200))
      scene.prepare(viewport: Size(width: width, height: 200))
      _ = scene.paint()
    }
    #expect(scene.textLayoutBuilds == 2)
  }
}
